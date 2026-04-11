//
//  IOSRateLimitRefreshController.swift
//  Codex Switcher iOS App
//
//  Created by Codex on 2026-04-11.
//

import Foundation
import Network
import Observation
import OSLog
import SwiftData
import SwiftUI

@MainActor
@Observable
final class IOSRateLimitRefreshController {
    private nonisolated static let pollCadence: Duration = .seconds(30)
    private nonisolated static let visibleRefreshInterval: TimeInterval = 5 * 60
    private nonisolated static let selectedRefreshInterval: TimeInterval = 90
    private nonisolated static let initialTransientBackoff: TimeInterval = 30
    private nonisolated static let maximumTransientBackoff: TimeInterval = 15 * 60
    private nonisolated static let authBackoff: TimeInterval = 30 * 60

    private let provider: CodexRateLimitProviding
    private let credentialStore: SyncedRateLimitCredentialStoring
    private let logger: Logger

    private var modelContext: ModelContext?
    private var pollingTask: Task<Void, Never>?
    private var visibleIdentityKeys: Set<String> = []
    private var selectedIdentityKey: String?
    private var snapshotsByIdentityKey: [String: CodexRateLimitSnapshot] = [:]
    private var refreshesInFlight: Set<String> = []
    private var backoffUntil: [String: Date] = [:]
    private var backoffSeconds: [String: TimeInterval] = [:]
    private var unauthorizedFingerprintByIdentityKey: [String: String] = [:]
    private var currentScenePhase: ScenePhase = .background
    private var pathMonitor: NWPathMonitor?

    init(
        provider: CodexRateLimitProviding = CodexRateLimitProvider(),
        credentialStore: SyncedRateLimitCredentialStoring = SyncedRateLimitCredentialStore(),
        logger: Logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "CodexSwitcher",
            category: "IOSRateLimitRefreshController"
        )
    ) {
        self.provider = provider
        self.credentialStore = credentialStore
        self.logger = logger
    }

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        startPathMonitorIfNeeded()
    }

    func setScenePhase(_ scenePhase: ScenePhase) {
        currentScenePhase = scenePhase

        if scenePhase == .active {
            startPollingIfNeeded()
            requestImmediateRefreshForTrackedAccounts()
        } else {
            stopPolling()
        }
    }

    func setVisible(_ isVisible: Bool, for identityKey: String) {
        let normalizedIdentityKey = normalizedIdentityKey(identityKey)
        guard !normalizedIdentityKey.isEmpty else {
            return
        }

        if isVisible {
            visibleIdentityKeys.insert(normalizedIdentityKey)
            requestImmediateRefresh(for: normalizedIdentityKey)
        } else {
            visibleIdentityKeys.remove(normalizedIdentityKey)
        }
    }

    func setSelected(identityKey: String?) {
        let normalizedIdentityKey = normalizedIdentityKey(identityKey)
        selectedIdentityKey = normalizedIdentityKey.isEmpty ? nil : normalizedIdentityKey

        if let selectedIdentityKey {
            requestImmediateRefresh(for: selectedIdentityKey)
        }
    }

    func reconcileKnownIdentityKeys(_ currentIdentityKeys: [String]) {
        let knownIdentityKeys = Set(
            currentIdentityKeys
                .map(normalizedIdentityKey)
                .filter { !$0.isEmpty }
        )

        visibleIdentityKeys = visibleIdentityKeys.intersection(knownIdentityKeys)

        if let selectedIdentityKey, !knownIdentityKeys.contains(selectedIdentityKey) {
            self.selectedIdentityKey = nil
        }

        snapshotsByIdentityKey = snapshotsByIdentityKey.filter { knownIdentityKeys.contains($0.key) }
        refreshesInFlight = refreshesInFlight.filter { knownIdentityKeys.contains($0) }
        backoffUntil = backoffUntil.filter { knownIdentityKeys.contains($0.key) }
        backoffSeconds = backoffSeconds.filter { knownIdentityKeys.contains($0.key) }
        unauthorizedFingerprintByIdentityKey = unauthorizedFingerprintByIdentityKey.filter { knownIdentityKeys.contains($0.key) }
    }

    func refreshNow(for identityKey: String) {
        let normalizedIdentityKey = normalizedIdentityKey(identityKey)
        guard !normalizedIdentityKey.isEmpty else {
            return
        }

        Task { await refreshIfNeeded(identityKey: normalizedIdentityKey, force: true) }
    }

    func refreshDueAccountsForTesting() async {
        await refreshDueAccounts()
    }

    func refreshNowForTesting(for identityKey: String) async {
        await refreshIfNeeded(identityKey: normalizedIdentityKey(identityKey), force: true)
    }

    private func startPollingIfNeeded() {
        guard pollingTask == nil else {
            return
        }

        pollingTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.refreshDueAccounts()
                try? await Task.sleep(for: Self.pollCadence)
            }
        }
    }

    private func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func startPathMonitorIfNeeded() {
        guard pathMonitor == nil else {
            return
        }

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else {
                return
            }

            Task { @MainActor [weak self] in
                guard let self, self.currentScenePhase == .active else {
                    return
                }

                self.requestImmediateRefreshForTrackedAccounts()
            }
        }

        monitor.start(queue: DispatchQueue(label: "com.marcel2215.codexswitcher.ios-ratelimit-network"))
        pathMonitor = monitor
    }

    private func requestImmediateRefreshForTrackedAccounts() {
        for identityKey in prioritizedIdentityKeys() {
            requestImmediateRefresh(for: identityKey)
        }
    }

    private func requestImmediateRefresh(for identityKey: String) {
        Task { await refreshIfNeeded(identityKey: identityKey, force: true) }
    }

    private func refreshDueAccounts() async {
        applyLocalResetsIfNeeded(relativeTo: .now)

        for identityKey in prioritizedIdentityKeys() {
            await refreshIfNeeded(identityKey: identityKey, force: false)
        }
    }

    private func prioritizedIdentityKeys() -> [String] {
        var ordered: [String] = []
        var seen = Set<String>()

        if let selectedIdentityKey, !selectedIdentityKey.isEmpty {
            ordered.append(selectedIdentityKey)
            seen.insert(selectedIdentityKey)
        }

        for identityKey in visibleIdentityKeys.sorted() where !seen.contains(identityKey) {
            ordered.append(identityKey)
            seen.insert(identityKey)
        }

        return ordered
    }

    private func refreshIfNeeded(identityKey: String, force: Bool) async {
        guard !identityKey.isEmpty else {
            return
        }

        guard !refreshesInFlight.contains(identityKey) else {
            return
        }

        guard
            let modelContext,
            let account = fetchAccount(identityKey: identityKey, in: modelContext)
        else {
            return
        }

        guard let syncedCredential = await bestAvailableCredential(for: identityKey, account: account) else {
            return
        }

        let now = Date()
        let credentialFingerprintChangedAfterUnauthorized: Bool
        if let unauthorizedFingerprint = unauthorizedFingerprintByIdentityKey[identityKey],
           unauthorizedFingerprint != syncedCredential.fingerprint {
            unauthorizedFingerprintByIdentityKey.removeValue(forKey: identityKey)
            backoffUntil.removeValue(forKey: identityKey)
            backoffSeconds.removeValue(forKey: identityKey)
            credentialFingerprintChangedAfterUnauthorized = true
        } else {
            credentialFingerprintChangedAfterUnauthorized = false
        }

        if let until = backoffUntil[identityKey], until > now {
            return
        }

        if !force, !credentialFingerprintChangedAfterUnauthorized {
            guard shouldRefresh(identityKey: identityKey, account: account, now: now) else {
                return
            }
        }

        refreshesInFlight.insert(identityKey)
        defer {
            refreshesInFlight.remove(identityKey)
        }

        let outcome = await provider.fetchSnapshot(
            for: CodexRateLimitRequest(
                identityKey: identityKey,
                credentials: syncedCredential.rateLimitCredentials,
                linkedLocation: nil,
                isCurrentAccount: false
            )
        )

        switch outcome {
        case .success(let snapshot):
            let adjustedSnapshot = snapshot.applyingResetBoundaries()
            snapshotsByIdentityKey[identityKey] = adjustedSnapshot
            backoffUntil.removeValue(forKey: identityKey)
            backoffSeconds.removeValue(forKey: identityKey)
            unauthorizedFingerprintByIdentityKey.removeValue(forKey: identityKey)

            if RateLimitAccountUpdater.apply(adjustedSnapshot, to: account) {
                do {
                    try modelContext.save()
                } catch {
                    logger.error("Couldn't save refreshed rate limits for \(identityKey, privacy: .private): \(String(describing: error), privacy: .private)")
                }
            }

        case .failure(.missingCredentials):
            return

        case .failure(.unauthorized):
            unauthorizedFingerprintByIdentityKey[identityKey] = syncedCredential.fingerprint
            backoffSeconds.removeValue(forKey: identityKey)
            backoffUntil[identityKey] = now.addingTimeInterval(Self.authBackoff)

        case .failure(.rateLimited(let retryAfter)):
            let requestedBackoff = retryAfter ?? nextTransientBackoff(for: identityKey)
            scheduleTransientBackoff(for: identityKey, seconds: requestedBackoff)

        case .failure:
            scheduleTransientBackoff(for: identityKey, seconds: nextTransientBackoff(for: identityKey))
        }
    }

    private func shouldRefresh(identityKey: String, account: StoredAccount, now: Date) -> Bool {
        let refreshInterval = identityKey == selectedIdentityKey
            ? Self.selectedRefreshInterval
            : Self.visibleRefreshInterval

        if let snapshot = snapshotsByIdentityKey[identityKey] {
            if let nextResetAt = snapshot.nextResetAt, now >= nextResetAt {
                return true
            }

            return now.timeIntervalSince(snapshot.fetchedAt) >= refreshInterval
        }

        if let observedAt = account.rateLimitsObservedAt {
            return now.timeIntervalSince(observedAt) >= refreshInterval
        }

        return true
    }

    private func nextTransientBackoff(for identityKey: String) -> TimeInterval {
        let currentBackoff = backoffSeconds[identityKey] ?? 0
        if currentBackoff <= 0 {
            return Self.initialTransientBackoff
        }

        return min(currentBackoff * 2, Self.maximumTransientBackoff)
    }

    private func scheduleTransientBackoff(for identityKey: String, seconds: TimeInterval) {
        let normalizedSeconds = max(seconds, 1)
        backoffSeconds[identityKey] = min(normalizedSeconds, Self.maximumTransientBackoff)
        backoffUntil[identityKey] = Date().addingTimeInterval(normalizedSeconds)
    }

    private func applyLocalResetsIfNeeded(relativeTo now: Date) {
        guard let modelContext else {
            return
        }

        do {
            let accountsByIdentityKey = firstAccountByIdentityKey(
                from: try modelContext.fetch(FetchDescriptor<StoredAccount>())
            )
            var didChange = false

            for (identityKey, snapshot) in snapshotsByIdentityKey {
                guard let account = accountsByIdentityKey[identityKey] else {
                    continue
                }

                let adjustedSnapshot = snapshot.applyingResetBoundaries(relativeTo: now)
                guard adjustedSnapshot != snapshot else {
                    continue
                }

                snapshotsByIdentityKey[identityKey] = adjustedSnapshot
                didChange = RateLimitAccountUpdater.apply(adjustedSnapshot, to: account) || didChange
            }

            if didChange {
                try modelContext.save()
            }
        } catch {
            logger.error("Couldn't apply local rate-limit resets on iOS: \(String(describing: error), privacy: .private)")
        }
    }

    private func fetchAccount(identityKey: String, in modelContext: ModelContext) -> StoredAccount? {
        let predicate = #Predicate<StoredAccount> { $0.identityKey == identityKey }
        var descriptor = FetchDescriptor<StoredAccount>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func bestAvailableCredential(
        for identityKey: String,
        account: StoredAccount
    ) async -> SyncedRateLimitCredential? {
        let cloudKitCredential = account.syncedRateLimitCredential(matching: identityKey)
        let keychainCredential: SyncedRateLimitCredential?

        do {
            keychainCredential = try await credentialStore.load(forIdentityKey: identityKey)
        } catch SyncedRateLimitCredentialStoreError.missingCredential {
            keychainCredential = nil
        } catch {
            logger.error("Couldn't load keychain-synced rate-limit credential for \(identityKey, privacy: .private): \(String(describing: error), privacy: .private)")
            keychainCredential = nil
        }

        switch (cloudKitCredential, keychainCredential) {
        case let (.some(cloudKitCredential), .some(keychainCredential)):
            return cloudKitCredential.exportedAt >= keychainCredential.exportedAt
                ? cloudKitCredential
                : keychainCredential
        case let (.some(cloudKitCredential), .none):
            return cloudKitCredential
        case let (.none, .some(keychainCredential)):
            return keychainCredential
        case (.none, .none):
            return nil
        }
    }

    private func normalizedIdentityKey(_ identityKey: String?) -> String {
        identityKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func firstAccountByIdentityKey(from accounts: [StoredAccount]) -> [String: StoredAccount] {
        var accountsByIdentityKey: [String: StoredAccount] = [:]

        for account in accounts {
            let identityKey = normalizedIdentityKey(account.identityKey)
            guard !identityKey.isEmpty else {
                continue
            }

            if accountsByIdentityKey[identityKey] == nil {
                accountsByIdentityKey[identityKey] = account
            }
        }

        return accountsByIdentityKey
    }
}
