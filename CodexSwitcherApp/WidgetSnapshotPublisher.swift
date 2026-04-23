//
//  WidgetSnapshotPublisher.swift
//  Codex Switcher
//
//  Created by Marcel Kwiatkowski on 2026-04-12.
//

import Foundation
import OSLog
import SwiftData

@MainActor
enum WidgetSnapshotPublisher {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "CodexSwitcher",
        category: "WidgetSnapshotPublisher"
    )
    private static let initialEmptyStoreFallbackWindow: TimeInterval = 30
    private static let launchedAt = Date()

    static var shouldAllowInitialEmptyStoreFallback: Bool {
        Date().timeIntervalSince(launchedAt) <= initialEmptyStoreFallbackWindow
    }

    static func publish(
        modelContext: ModelContext,
        currentAccountID: String? = nil,
        selectedAccountID: String? = nil,
        selectedAccountIsLive: Bool = false,
        allowEmptyStoreFallback: Bool = false
    ) {
        let store = CodexSharedStateStore()
        let snapshotAvailabilityStore = LocalAccountSnapshotAvailabilityStore()
        let descriptor = FetchDescriptor<StoredAccount>(
            sortBy: [
                SortDescriptor(\.customOrder),
                SortDescriptor(\.createdAt),
            ]
        )

        let accounts = (try? modelContext.fetch(descriptor)) ?? []
        let sharedAccounts = accounts
            .filter { !$0.identityKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { account in
                SharedCodexAccountRecord(
                    id: account.identityKey,
                    name: account.name,
                    iconSystemName: account.iconSystemName,
                    emailHint: account.emailHint,
                    accountIdentifier: account.accountIdentifier,
                    authModeRaw: account.authModeRaw,
                    lastLoginAt: account.lastLoginAt,
                    sevenDayLimitUsedPercent: account.sevenDayLimitUsedPercent,
                    fiveHourLimitUsedPercent: account.fiveHourLimitUsedPercent,
                    sevenDayResetsAt: account.sevenDayResetsAt,
                    fiveHourResetsAt: account.fiveHourResetsAt,
                    sevenDayDataStatusRaw: account.sevenDayDataStatus.rawValue,
                    fiveHourDataStatusRaw: account.fiveHourDataStatus.rawValue,
                    rateLimitsObservedAt: account.rateLimitsObservedAt,
                    sortOrder: account.customOrder,
                    isPinned: account.isPinned,
                    hasLocalSnapshot: snapshotAvailabilityStore.containsSnapshot(forIdentityKey: account.identityKey)
                )
            }

        let existingState = (try? store.load()) ?? .empty
        let resolvedAccounts = mergedAccounts(
            localAccounts: sharedAccounts,
            existingState: existingState,
            allowEmptyStoreFallback: allowEmptyStoreFallback
        )
        let sharedState = SharedCodexState(
            schemaVersion: SharedCodexState.currentSchemaVersion,
            authState: .ready,
            linkedFolderPath: nil,
            currentAccountID: currentAccountID,
            selectedAccountID: selectedAccountID,
            selectedAccountIsLive: selectedAccountIsLive,
            accounts: resolvedAccounts,
            updatedAt: .now
        )

        do {
            try store.save(sharedState)
            Task(priority: .utility) {
                await RateLimitResetNotificationScheduler.shared.synchronize(with: sharedState)
                do {
                    try await CodexSpotlightIndexer.refresh(with: sharedState)
                } catch {
                    logger.error("Couldn't refresh Spotlight index: \(String(describing: error), privacy: .private)")
                }
            }
            CodexSharedSurfaceReloader.reloadAllRateLimitWidgets()
        } catch {
            logger.error("Couldn't publish widget snapshot: \(String(describing: error), privacy: .private)")
        }
    }

    static func mergedAccounts(
        localAccounts: [SharedCodexAccountRecord],
        existingState: SharedCodexState,
        allowEmptyStoreFallback: Bool
    ) -> [SharedCodexAccountRecord] {
        guard allowEmptyStoreFallback,
              localAccounts.isEmpty,
              !existingState.accounts.isEmpty else {
            return localAccounts
        }

        // iPhone/watch can briefly boot before CloudKit replays the local
        // account store. Limit the stale-state fallback to a short startup
        // window so real deletions eventually propagate through widgets.
        return existingState.accounts
    }

    static func fingerprint(for accounts: [StoredAccount]) -> Int {
        var hasher = Hasher()
        let snapshotAvailabilityStore = LocalAccountSnapshotAvailabilityStore()

        for account in accounts.sorted(by: widgetSortComparator) {
            hasher.combine(account.id)
            hasher.combine(account.identityKey)
            hasher.combine(account.name)
            hasher.combine(account.iconSystemName)
            hasher.combine(account.emailHint)
            hasher.combine(account.accountIdentifier)
            hasher.combine(account.authModeRaw)
            hasher.combine(account.lastLoginAt)
            hasher.combine(account.customOrder)
            hasher.combine(account.isPinned)
            hasher.combine(account.sevenDayLimitUsedPercent)
            hasher.combine(account.fiveHourLimitUsedPercent)
            hasher.combine(account.sevenDayResetsAt)
            hasher.combine(account.fiveHourResetsAt)
            hasher.combine(account.sevenDayDataStatus.rawValue)
            hasher.combine(account.fiveHourDataStatus.rawValue)
            hasher.combine(account.rateLimitsObservedAt)
            hasher.combine(snapshotAvailabilityStore.containsSnapshot(forIdentityKey: account.identityKey))
        }

        return hasher.finalize()
    }

    private static func widgetSortComparator(lhs: StoredAccount, rhs: StoredAccount) -> Bool {
        AccountsPresentationLogic.storedAccountCustomOrderComparator(lhs: lhs, rhs: rhs)
    }
}
