//
//  RateLimitResetNotificationScheduler.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-13.
//

import Foundation
import OSLog
@preconcurrency import UserNotifications

actor RateLimitResetNotificationScheduler {
    static let shared = RateLimitResetNotificationScheduler()

    private struct PendingResetNotification {
        let identifier: String
        let content: UNMutableNotificationContent
        let timeInterval: TimeInterval
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

        var isEnabled: Bool {
            switch self {
            case .fiveHour:
                CodexSharedPreferences.fiveHourResetNotificationsEnabled
            case .sevenDay:
                CodexSharedPreferences.sevenDayResetNotificationsEnabled
            }
        }
    }

    private static let identifierPrefix = "com.marcel2215.codexswitcher.rate-limit-reset."
    private let center: UNUserNotificationCenter
    private let stateStore: CodexSharedStateStore
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "CodexSwitcher",
        category: "RateLimitResetNotifications"
    )

    init(
        center: UNUserNotificationCenter = .current(),
        stateStore: CodexSharedStateStore = .init()
    ) {
        self.center = center
        self.stateStore = stateStore
    }

    func synchronizeWithStoredState() async {
        let sharedState = (try? stateStore.load()) ?? .empty
        await synchronize(with: sharedState)
    }

    func synchronize(with sharedState: SharedCodexState) async {
        let existingIdentifiers = await notificationIdentifiersWithManagedPrefix()
        let settings = await center.notificationSettings()

        guard
            CodexSharedPreferences.hasAnyRateLimitResetNotificationsEnabled,
            CodexNotificationAuthorization.isDeliveryAuthorized(settings.authorizationStatus)
        else {
            removeManagedNotifications(identifiers: existingIdentifiers)
            return
        }

        let now = Date()
        let scheduledNotifications = sharedState.accounts
            .sorted { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder {
                    return lhs.sortOrder < rhs.sortOrder
                }

                return lhs.id < rhs.id
            }
            .flatMap { account in
                ResetWindow.allCases.compactMap { makePendingNotification(for: account, window: $0, now: now) }
            }

        removeManagedNotifications(identifiers: existingIdentifiers)

        for notification in scheduledNotifications {
            let request = UNNotificationRequest(
                identifier: notification.identifier,
                content: notification.content,
                trigger: UNTimeIntervalNotificationTrigger(
                    timeInterval: notification.timeInterval,
                    repeats: false
                )
            )

            do {
                try await addNotificationRequest(request)
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
        now: Date
    ) -> PendingResetNotification? {
        guard window.isEnabled else {
            return nil
        }

        let metricStatus: RateLimitMetricDataStatus
        let resetDate: Date?

        switch window {
        case .fiveHour:
            metricStatus = account.fiveHourDataStatus
            resetDate = account.fiveHourResetsAt
        case .sevenDay:
            metricStatus = account.sevenDayDataStatus
            resetDate = account.sevenDayResetsAt
        }

        guard metricStatus == .exact, let resetDate else {
            return nil
        }

        let timeInterval = resetDate.timeIntervalSince(now)
        guard timeInterval > 1 else {
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
            timeInterval: timeInterval
        )
    }

    private func notificationIdentifiersWithManagedPrefix() async -> [String] {
        let pendingIdentifiers = await pendingManagedNotificationIdentifiers()
        let deliveredIdentifiers = await deliveredManagedNotificationIdentifiers()
        return Array(Set(pendingIdentifiers + deliveredIdentifiers))
    }

    private func removeManagedNotifications(identifiers: [String]) {
        guard !identifiers.isEmpty else {
            return
        }

        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    private func addNotificationRequest(_ request: UNNotificationRequest) async throws {
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

    private func pendingManagedNotificationIdentifiers() async -> [String] {
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

    private func deliveredManagedNotificationIdentifiers() async -> [String] {
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
