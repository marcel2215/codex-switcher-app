//
//  ForegroundRateLimitRefreshController.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-12.
//

import Foundation
import Observation
import OSLog
import SwiftData
import SwiftUI

#if canImport(Network) && !os(watchOS)
import Network
#endif

struct ForegroundRateLimitRefreshPolicy: Sendable, Equatable {
    let pollCadence: Duration
    let visibleRefreshInterval: TimeInterval
    let selectedRefreshInterval: TimeInterval
    let initialTransientBackoff: TimeInterval
    let maximumTransientBackoff: TimeInterval
    let authBackoff: TimeInterval
    let supportsPathMonitoring: Bool

    static let iOS = Self(
        pollCadence: .seconds(30),
        visibleRefreshInterval: 5 * 60,
        selectedRefreshInterval: 90,
        initialTransientBackoff: 30,
        maximumTransientBackoff: 15 * 60,
        authBackoff: 30 * 60,
        supportsPathMonitoring: true
    )

    static let watchOS = Self(
        pollCadence: .seconds(45),
        visibleRefreshInterval: 10 * 60,
        selectedRefreshInterval: 120,
        initialTransientBackoff: 60,
        maximumTransientBackoff: 30 * 60,
        authBackoff: 60 * 60,
        supportsPathMonitoring: false
    )
}

@MainActor
@Observable
final class ForegroundRateLimitRefreshController {
    private let policy: ForegroundRateLimitRefreshPolicy
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

#if canImport(Network) && !os(watchOS)
    @ObservationIgnored private var pathMonitor: NWPathMonitor?
    @ObservationIgnored private var lastPathSatisfied = false
#endif

    init(
        policy: ForegroundRateLimitRefreshPolicy,
        provider: CodexRateLimitProviding = CodexRateLimitProvider(),
        credentialStore: SyncedRateLimitCredentialStoring = SyncedRateLimitCredentialStore(),
        logger: Logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "CodexSwitcher",
            category: "ForegroundRateLimitRefreshController"
        )
    ) {
        self.policy = policy
        self.provider = provider
        self.credentialStore = credentialStore
        self.logger = logger
    }

    deinit {
        MainActor.assumeIsolated {
            pollingTask?.cancel()
#if canImport(Network) && !os(watchOS)
            pathMonitor?.cancel()
#endif
        }
    }

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        startPathMonitorIfNeeded()
    }

    func setScenePhase(_ scenePhase: ScenePhase) {
        currentScenePhase = scenePhase

        if scenePhase == .active {
            startPollingIfNeeded()
            requestTrackedAccountsRefresh(force: false)
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
            let inserted = visibleIdentityKeys.insert(normalizedIdentityKey).inserted
            guard inserted else {
                return
            }

            Task { await refreshIfNeeded(identityKey: normalizedIdentityKey, force: false) }
        } else {
            visibleIdentityKeys.remove(normalizedIdentityKey)
        }
    }

    func setSelected(identityKey: String?) {
        let normalizedIdentityKey = normalizedIdentityKey(identityKey)
        selectedIdentityKey = normalizedIdentityKey.isEmpty ? nil : normalizedIdentityKey

        if let selectedIdentityKey {
            requestImmediateRefresh(for: selectedIdentityKey, force: true)
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

    func refreshTrackedAccountsNow() async {
        for identityKey in prioritizedIdentityKeys() {
            await refreshIfNeeded(identityKey: identityKey, force: true)
        }
    }

    func refreshNowAndWait(for identityKey: String) async {
        await refreshIfNeeded(identityKey: normalizedIdentityKey(identityKey), force: true)
    }

    func hasSyncedCredential(for identityKey: String) async -> Bool {
        let normalizedIdentityKey = normalizedIdentityKey(identityKey)
        guard !normalizedIdentityKey.isEmpty else {
            return false
        }

        return await credentialStore.containsCredential(forIdentityKey: normalizedIdentityKey)
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
                try? await Task.sleep(for: policy.pollCadence)
            }
        }
    }

    private func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func startPathMonitorIfNeeded() {
#if canImport(Network) && !os(watchOS)
        guard policy.supportsPathMonitoring else {
            return
        }

        guard pathMonitor == nil else {
            return
        }

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                let isSatisfied = path.status == .satisfied
                defer { self.lastPathSatisfied = isSatisfied }

                guard isSatisfied, !self.lastPathSatisfied, self.currentScenePhase == .active else {
                    return
                }

                self.requestTrackedAccountsRefresh(force: true)
            }
        }

        monitor.start(queue: DispatchQueue(label: "com.marcel2215.codexswitcher.ratelimit-network"))
        pathMonitor = monitor
#endif
    }

    private func requestTrackedAccountsRefresh(force: Bool) {
        for identityKey in prioritizedIdentityKeys() {
            requestImmediateRefresh(for: identityKey, force: force)
        }
    }

    private func requestImmediateRefresh(for identityKey: String, force: Bool) {
        Task { await refreshIfNeeded(identityKey: identityKey, force: force) }
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

        guard let modelContext, !Task.isCancelled else {
            return
        }

        let accounts = fetchAccounts(identityKey: identityKey, in: modelContext)
        guard let referenceAccount = refreshReferenceAccount(from: accounts) else {
            return
        }

        let now = Date()
        let hasUnauthorizedBackoff = unauthorizedFingerprintByIdentityKey[identityKey] != nil
        if !force && !hasUnauthorizedBackoff {
            guard shouldRefresh(identityKey: identityKey, account: referenceAccount, now: now) else {
                return
            }
        }

        guard let syncedCredential = await bestAvailableCredential(for: identityKey) else {
            return
        }

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

        if !force, hasUnauthorizedBackoff, !credentialFingerprintChangedAfterUnauthorized {
            guard shouldRefresh(identityKey: identityKey, account: referenceAccount, now: now) else {
                return
            }
        }

        refreshesInFlight.insert(identityKey)
        defer { refreshesInFlight.remove(identityKey) }

        let result = await provider.fetchSnapshot(
            for: CodexRateLimitRequest(
                identityKey: identityKey,
                credentials: syncedCredential.rateLimitCredentials,
                linkedLocation: nil,
                isCurrentAccount: false
            )
        )

        if let snapshot = result.snapshot {
            let adjustedSnapshot = snapshot.applyingResetBoundaries()
            snapshotsByIdentityKey[identityKey] = adjustedSnapshot

            var didChange = false
            for account in accounts {
                didChange = RateLimitAccountUpdater.apply(adjustedSnapshot, to: account) || didChange
            }

            if didChange {
                do {
                    try modelContext.save()
                } catch {
                    logger.error("Couldn't save refreshed rate limits for \(identityKey, privacy: .private): \(String(describing: error), privacy: .private)")
                }
            }
        }

        switch result.remoteFailure {
        case nil:
            backoffUntil.removeValue(forKey: identityKey)
            backoffSeconds.removeValue(forKey: identityKey)
            unauthorizedFingerprintByIdentityKey.removeValue(forKey: identityKey)

        case .some(.missingCredentials), .some(.cancelled):
            return

        case .some(.unauthorized):
            unauthorizedFingerprintByIdentityKey[identityKey] = syncedCredential.fingerprint
            backoffSeconds.removeValue(forKey: identityKey)
            backoffUntil[identityKey] = now.addingTimeInterval(policy.authBackoff)

        case .some(.rateLimited(let retryAfter)):
            let requestedBackoff = retryAfter ?? nextTransientBackoff(for: identityKey)
            scheduleTransientBackoff(for: identityKey, seconds: requestedBackoff)

        case .some:
            scheduleTransientBackoff(for: identityKey, seconds: nextTransientBackoff(for: identityKey))
        }
    }

    private func shouldRefresh(identityKey: String, account: StoredAccount, now: Date) -> Bool {
        let refreshInterval = identityKey == selectedIdentityKey
            ? policy.selectedRefreshInterval
            : policy.visibleRefreshInterval

        if let snapshot = snapshotsByIdentityKey[identityKey] ?? storedSnapshot(from: account) {
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
            return policy.initialTransientBackoff
        }

        return min(currentBackoff * 2, policy.maximumTransientBackoff)
    }

    private func scheduleTransientBackoff(for identityKey: String, seconds: TimeInterval) {
        let normalizedSeconds = max(seconds, 1)
        let cappedSeconds = min(normalizedSeconds, policy.maximumTransientBackoff)
        backoffSeconds[identityKey] = cappedSeconds
        backoffUntil[identityKey] = Date().addingTimeInterval(cappedSeconds)
    }

    private func applyLocalResetsIfNeeded(relativeTo now: Date) {
        guard let modelContext else {
            return
        }

        do {
            let accountsByIdentityKey = groupedAccountsByIdentityKey(
                from: try modelContext.fetch(FetchDescriptor<StoredAccount>())
            )
            var didChange = false

            for (identityKey, accounts) in accountsByIdentityKey {
                guard let baseSnapshot = snapshotsByIdentityKey[identityKey] ?? storedSnapshot(from: accounts) else {
                    continue
                }

                let adjustedSnapshot = baseSnapshot.applyingResetBoundaries(relativeTo: now)
                guard adjustedSnapshot != baseSnapshot else {
                    continue
                }

                snapshotsByIdentityKey[identityKey] = adjustedSnapshot
                for account in accounts {
                    didChange = RateLimitAccountUpdater.apply(adjustedSnapshot, to: account) || didChange
                }
            }

            if didChange {
                try modelContext.save()
            }
        } catch {
            logger.error("Couldn't apply local rate-limit resets: \(String(describing: error), privacy: .private)")
        }
    }

    private func fetchAccounts(identityKey: String, in modelContext: ModelContext) -> [StoredAccount] {
        let predicate = #Predicate<StoredAccount> { $0.identityKey == identityKey }
        let descriptor = FetchDescriptor<StoredAccount>(predicate: predicate)
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func bestAvailableCredential(for identityKey: String) async -> SyncedRateLimitCredential? {
        do {
            return try await credentialStore.load(forIdentityKey: identityKey)
        } catch SyncedRateLimitCredentialStoreError.missingCredential {
            return nil
        } catch {
            logger.error("Couldn't load synced rate-limit credential for \(identityKey, privacy: .private): \(String(describing: error), privacy: .private)")
            return nil
        }
    }

    private func storedSnapshot(from account: StoredAccount) -> CodexRateLimitSnapshot? {
        guard
            account.rateLimitsObservedAt != nil
                || account.sevenDayLimitUsedPercent != nil
                || account.fiveHourLimitUsedPercent != nil
                || account.sevenDayResetsAt != nil
                || account.fiveHourResetsAt != nil
        else {
            return nil
        }

        let observedAt = account.rateLimitsObservedAt ?? .distantPast
        return CodexRateLimitSnapshot(
            identityKey: account.identityKey,
            observedAt: observedAt,
            fetchedAt: observedAt,
            source: .remoteUsageAPI,
            sevenDayRemainingPercent: account.sevenDayLimitUsedPercent,
            fiveHourRemainingPercent: account.fiveHourLimitUsedPercent,
            sevenDayResetsAt: account.sevenDayResetsAt,
            fiveHourResetsAt: account.fiveHourResetsAt
        )
    }

    private func storedSnapshot(from accounts: [StoredAccount]) -> CodexRateLimitSnapshot? {
        accounts
            .compactMap { storedSnapshot(from: $0) }
            .max { lhs, rhs in
                if lhs.observedAt == rhs.observedAt {
                    return lhs.fetchedAt < rhs.fetchedAt
                }

                return lhs.observedAt < rhs.observedAt
            }
    }

    private func normalizedIdentityKey(_ identityKey: String?) -> String {
        identityKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func refreshReferenceAccount(from accounts: [StoredAccount]) -> StoredAccount? {
        accounts.max { lhs, rhs in
            let lhsObservedAt = lhs.rateLimitsObservedAt ?? .distantPast
            let rhsObservedAt = rhs.rateLimitsObservedAt ?? .distantPast
            if lhsObservedAt == rhsObservedAt {
                return lhs.createdAt < rhs.createdAt
            }

            return lhsObservedAt < rhsObservedAt
        }
    }

    private func groupedAccountsByIdentityKey(from accounts: [StoredAccount]) -> [String: [StoredAccount]] {
        var accountsByIdentityKey: [String: [StoredAccount]] = [:]

        for account in accounts {
            let identityKey = normalizedIdentityKey(account.identityKey)
            guard !identityKey.isEmpty else {
                continue
            }

            accountsByIdentityKey[identityKey, default: []].append(account)
        }

        return accountsByIdentityKey
    }
}
