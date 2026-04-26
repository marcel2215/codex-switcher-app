//
//  RateLimitResetNotificationScheduler.swift
//  Codex Switcher
//
//  Created by Marcel Kwiatkowski on 2026-04-13.
//

import Foundation
import OSLog
@preconcurrency import UserNotifications

actor RateLimitResetNotificationScheduler {
    static let shared = RateLimitResetNotificationScheduler()

    struct NotificationPreferences: Sendable, Equatable {
        let fiveHourEnabled: Bool
        let sevenDayEnabled: Bool

        var hasAnyEnabled: Bool {
            fiveHourEnabled || sevenDayEnabled
        }
    }

    private struct PendingResetNotification {
        let identifier: String
        let content: UNMutableNotificationContent
        let fireDate: Date
        let isCurrentAccount: Bool
        let isPinnedAccount: Bool
    }

    private enum ResetWindow: String, CaseIterable, Sendable {
        case fiveHour
        case sevenDay

        var identifierComponent: String {
            switch self {
            case .fiveHour:
                "five-hour"
            case .sevenDay:
                "seven-day"
            }
        }

        var title: String {
            switch self {
            case .fiveHour:
                "5-Hour Rate Limit Reset"
            case .sevenDay:
                "7-Day Rate Limit Reset"
            }
        }

        var bodyLabel: String {
            switch self {
            case .fiveHour:
                "5-hour"
            case .sevenDay:
                "7-day"
            }
        }

        func isEnabled(in preferences: NotificationPreferences) -> Bool {
            switch self {
            case .fiveHour:
                preferences.fiveHourEnabled
            case .sevenDay:
                preferences.sevenDayEnabled
            }
        }
    }

    private static let identifierPrefix = "com.marcel2215.codexswitcher.rate-limit-reset."
    private static let maximumPendingResetNotifications = 48
    private let stateStore: CodexSharedStateStore
    private let notificationPreferencesProvider: @Sendable () -> NotificationPreferences
    private let authorizationStatusProvider: @Sendable () async -> UNAuthorizationStatus
    private let addNotificationRequestHandler: @Sendable (UNNotificationRequest) async throws -> Void
    private let pendingNotificationIdentifiersProvider: @Sendable () async -> [String]
    private let deliveredNotificationIdentifiersProvider: @Sendable () async -> [String]
    private let removeNotificationsHandler: @Sendable ([String]) -> Void
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "CodexSwitcher",
        category: "RateLimitResetNotifications"
    )

    init(
        center: UNUserNotificationCenter = .current(),
        stateStore: CodexSharedStateStore = .init(),
        notificationPreferencesProvider: (@Sendable () -> NotificationPreferences)? = nil,
        authorizationStatusProvider: (@Sendable () async -> UNAuthorizationStatus)? = nil,
        addNotificationRequestHandler: (@Sendable (UNNotificationRequest) async throws -> Void)? = nil,
        pendingNotificationIdentifiersProvider: (@Sendable () async -> [String])? = nil,
        deliveredNotificationIdentifiersProvider: (@Sendable () async -> [String])? = nil,
        removeNotificationsHandler: (@Sendable ([String]) -> Void)? = nil
    ) {
        self.stateStore = stateStore
        self.notificationPreferencesProvider = notificationPreferencesProvider ?? {
            NotificationPreferences(
                fiveHourEnabled: CodexSharedPreferences.fiveHourResetNotificationsEnabled,
                sevenDayEnabled: CodexSharedPreferences.sevenDayResetNotificationsEnabled
            )
        }
        self.authorizationStatusProvider = authorizationStatusProvider ?? {
            let settings = await center.notificationSettings()
            return settings.authorizationStatus
        }
        self.addNotificationRequestHandler = addNotificationRequestHandler ?? {
            try await Self.addNotificationRequest($0, to: center)
        }
        self.pendingNotificationIdentifiersProvider = pendingNotificationIdentifiersProvider ?? {
            await Self.pendingManagedNotificationIdentifiers(from: center)
        }
        self.deliveredNotificationIdentifiersProvider = deliveredNotificationIdentifiersProvider ?? {
            await Self.deliveredManagedNotificationIdentifiers(from: center)
        }
        self.removeNotificationsHandler = removeNotificationsHandler ?? {
            center.removePendingNotificationRequests(withIdentifiers: $0)
            center.removeDeliveredNotifications(withIdentifiers: $0)
        }
    }

    func synchronizeWithStoredState() async {
        let sharedState = stateStore.loadBestEffort()
        await synchronize(with: sharedState)
    }

    func synchronize(with sharedState: SharedCodexState) async {
        let existingIdentifiers = await notificationIdentifiersWithManagedPrefix()
        let notificationPreferences = notificationPreferencesProvider()
        let authorizationStatus = await authorizationStatusProvider()

        guard
            notificationPreferences.hasAnyEnabled,
            CodexNotificationAuthorization.isDeliveryAuthorized(authorizationStatus)
        else {
            removeManagedNotifications(identifiers: existingIdentifiers)
            return
        }

        let now = Date()
        let scheduledNotifications = sharedState.accounts
            .sorted { lhs, rhs in
                AccountsPresentationLogic.sharedAccountRecordComparator(lhs: lhs, rhs: rhs)
            }
            .flatMap { account in
                ResetWindow.allCases.compactMap {
                    makePendingNotification(
                        for: account,
                        window: $0,
                        preferences: notificationPreferences,
                        currentAccountID: sharedState.currentAccountID,
                        now: now
                    )
                }
            }
            .sorted(by: resetNotificationComparator)
            .prefix(Self.maximumPendingResetNotifications)

        let desiredIdentifiers = Set(scheduledNotifications.map(\.identifier))
        let staleIdentifiers = existingIdentifiers.filter {
            !desiredIdentifiers.contains($0)
        }

        removeManagedNotifications(identifiers: staleIdentifiers)

        for notification in scheduledNotifications {
            let request = UNNotificationRequest(
                identifier: notification.identifier,
                content: notification.content,
                trigger: UNTimeIntervalNotificationTrigger(
                    timeInterval: max(notification.fireDate.timeIntervalSinceNow, 1),
                    repeats: false
                )
            )

            do {
                try await addNotificationRequestHandler(request)
            } catch {
                logger.error(
                    "Couldn't schedule rate-limit reset notification \(notification.identifier, privacy: .public): \(String(describing: error), privacy: .private)"
                )
            }
        }
    }

    private func makePendingNotification(
        for account: SharedCodexAccountRecord,
        window: ResetWindow,
        preferences: NotificationPreferences,
        currentAccountID: String?,
        now: Date
    ) -> PendingResetNotification? {
        guard window.isEnabled(in: preferences) else {
            return nil
        }

        let metricStatus: RateLimitMetricDataStatus
        let remainingPercent: Int?
        let resetDate: Date?

        switch window {
        case .fiveHour:
            metricStatus = account.fiveHourDataStatus
            remainingPercent = account.fiveHourLimitUsedPercent
            resetDate = account.fiveHourResetsAt
        case .sevenDay:
            metricStatus = account.sevenDayDataStatus
            remainingPercent = account.sevenDayLimitUsedPercent
            resetDate = account.sevenDayResetsAt
        }

        let normalizedRemainingPercent = remainingPercent.map { min(max($0, 0), 100) }

        guard metricStatus == .exact, let normalizedRemainingPercent, normalizedRemainingPercent < 100, let resetDate else {
            return nil
        }

        guard resetDate.timeIntervalSince(now) > 1 else {
            return nil
        }

        let trimmedAccountName = account.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let accountName = trimmedAccountName.isEmpty ? "Your account" : trimmedAccountName

        let content = UNMutableNotificationContent()
        content.title = window.title
        content.body = "\(accountName) is back to 100% for its \(window.bodyLabel) window."
        content.threadIdentifier = "rate-limit-reset"

        return PendingResetNotification(
            identifier: Self.identifierPrefix + window.identifierComponent + "." + hexEncoded(account.id),
            content: content,
            fireDate: resetDate,
            isCurrentAccount: account.id == currentAccountID,
            isPinnedAccount: account.isPinned
        )
    }

    private func resetNotificationComparator(
        lhs: PendingResetNotification,
        rhs: PendingResetNotification
    ) -> Bool {
        if lhs.isCurrentAccount != rhs.isCurrentAccount {
            return lhs.isCurrentAccount
        }

        if lhs.isPinnedAccount != rhs.isPinnedAccount {
            return lhs.isPinnedAccount
        }

        if lhs.fireDate != rhs.fireDate {
            return lhs.fireDate < rhs.fireDate
        }

        return lhs.identifier < rhs.identifier
    }

    private func notificationIdentifiersWithManagedPrefix() async -> [String] {
        let pendingIdentifiers = await pendingNotificationIdentifiersProvider()
        let deliveredIdentifiers = await deliveredNotificationIdentifiersProvider()
        return Array(Set(pendingIdentifiers + deliveredIdentifiers))
    }

    private func removeManagedNotifications(identifiers: [String]) {
        guard !identifiers.isEmpty else {
            return
        }

        removeNotificationsHandler(identifiers)
    }

    private nonisolated static func addNotificationRequest(
        _ request: UNNotificationRequest,
        to center: UNUserNotificationCenter
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            center.add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private nonisolated static func pendingManagedNotificationIdentifiers(
        from center: UNUserNotificationCenter
    ) async -> [String] {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                continuation.resume(
                    returning: requests
                        .map(\.identifier)
                        .filter { $0.hasPrefix(Self.identifierPrefix) }
                )
            }
        }
    }

    private nonisolated static func deliveredManagedNotificationIdentifiers(
        from center: UNUserNotificationCenter
    ) async -> [String] {
        await withCheckedContinuation { continuation in
            center.getDeliveredNotifications { notifications in
                continuation.resume(
                    returning: notifications
                        .map(\.request.identifier)
                        .filter { $0.hasPrefix(Self.identifierPrefix) }
                )
            }
        }
    }

    /// Notification request identifiers need stable characters so updates can
    /// reliably replace stale requests after account renames or data refreshes.
    private func hexEncoded(_ value: String) -> String {
        value.utf8.map { String(format: "%02x", $0) }.joined()
    }
}
