//
//  BackgroundAppRefreshCoordinator.swift
//  Codex Switcher
//
//  Created by Marcel Kwiatkowski on 2026-04-14.
//

import BackgroundTasks
import Foundation
import OSLog
import SwiftData
import UIKit

@MainActor
final class IOSBackgroundAppRefreshCoordinator {
    nonisolated static let taskIdentifier = "com.marcel2215.codexswitcher.app-refresh"
    nonisolated static let earliestBeginInterval: TimeInterval = 15 * 60

    static let shared = IOSBackgroundAppRefreshCoordinator()

    private let provider: CodexRateLimitProviding
    private let credentialStore: SyncedRateLimitCredentialStoring
    private let logger: Logger
    private let backgroundRefreshStatusProvider: @MainActor () -> UIBackgroundRefreshStatus
    private let submitRequest: @Sendable (BGAppRefreshTaskRequest) throws -> Void
    private let cancelRequest: @Sendable (String) -> Void
    private let publishSnapshot: @MainActor (ModelContext) -> Void

    init(
        provider: CodexRateLimitProviding = CodexRateLimitProvider(),
        credentialStore: SyncedRateLimitCredentialStoring = SyncedRateLimitCredentialStore(),
        backgroundRefreshStatusProvider: @escaping @MainActor () -> UIBackgroundRefreshStatus = {
            UIApplication.shared.backgroundRefreshStatus
        },
        submitRequest: @escaping @Sendable (BGAppRefreshTaskRequest) throws -> Void = {
            try BGTaskScheduler.shared.submit($0)
        },
        cancelRequest: @escaping @Sendable (String) -> Void = {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: $0)
        },
        publishSnapshot: @escaping @MainActor (ModelContext) -> Void = {
            WidgetSnapshotPublisher.publish(modelContext: $0)
        },
        logger: Logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "CodexSwitcher",
            category: "IOSBackgroundAppRefreshCoordinator"
        )
    ) {
        self.provider = provider
        self.credentialStore = credentialStore
        self.backgroundRefreshStatusProvider = backgroundRefreshStatusProvider
        self.submitRequest = submitRequest
        self.cancelRequest = cancelRequest
        self.publishSnapshot = publishSnapshot
        self.logger = logger
    }

    func scheduleNextRefresh(after interval: TimeInterval = earliestBeginInterval) {
        // The system may drop or defer requests, so always keep a single freshest request queued.
        guard backgroundRefreshStatusProvider() == .available else {
            logger.info("Skipping background app refresh scheduling because Background App Refresh is unavailable.")
            return
        }

        cancelRequest(Self.taskIdentifier)

        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: max(interval, 0))

        do {
            try submitRequest(request)
        } catch {
            logger.error("Couldn't schedule background app refresh: \(String(describing: error), privacy: .private)")
        }
    }

    func handleScheduledRefresh() async {
        defer { scheduleNextRefresh() }

        do {
            let modelContainer = try IOSAppBootstrap.makePersistentModelContainer()
            _ = await performRefresh(using: modelContainer)
        } catch {
            logger.error("Couldn't initialize persistent storage for background app refresh: \(String(describing: error), privacy: .private)")
        }
    }

    @discardableResult
    func performRefresh(using modelContainer: ModelContainer) async -> Bool {
        let modelContext = modelContainer.mainContext
        let identityKeys = loadTrackedIdentityKeys(from: modelContext)

        // Reuse the main refresh engine so background updates honor the same auth, retry, and backoff rules.
        let engine = ForegroundRateLimitRefreshController(
            policy: .iOSBackgroundTask,
            provider: provider,
            credentialStore: credentialStore,
            logger: logger
        )
        engine.configure(modelContext: modelContext)
        await engine.refreshTrackedAccountsForBackground(identityKeys: identityKeys)
        publishSnapshot(modelContext)
        return true
    }

    private func loadTrackedIdentityKeys(from modelContext: ModelContext) -> [String] {
        let descriptor = FetchDescriptor<StoredAccount>(
            sortBy: [
                SortDescriptor(\.customOrder),
                SortDescriptor(\.createdAt),
            ]
        )
        let accounts = (try? modelContext.fetch(descriptor)) ?? []
        var seen = Set<String>()

        return accounts.compactMap { account in
            let identityKey = account.identityKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !identityKey.isEmpty else {
                return nil
            }

            guard seen.insert(identityKey).inserted else {
                return nil
            }

            return identityKey
        }
    }
}
