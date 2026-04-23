//
//  AccountSwitchNotificationManager.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-07.
//

import Foundation
import UserNotifications

@MainActor
protocol AccountSwitchNotifying: AnyObject {
    func postSwitchNotification(for accountName: String, kind: CodexSwitchNotificationKind) async
    func requestAuthorizationForNotificationsPreference() async -> NotificationAuthorizationRequestResult
}

@MainActor
final class AccountSwitchNotificationManager: AccountSwitchNotifying {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func postSwitchNotification(for accountName: String, kind: CodexSwitchNotificationKind) async {
        guard CodexSharedPreferences.accountSwitchNotificationsEnabled else {
            return
        }

        guard let content = CodexSharedSwitchNotificationContent.makeContent(
            accountName: accountName,
            kind: kind
        ) else {
            return
        }

        let settings = await center.notificationSettings()
        guard CodexNotificationAuthorization.isDeliveryAuthorized(settings.authorizationStatus) else {
            return
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        )

        do {
            try await add(request)
        } catch {
            // Failing to post a desktop notification should not block switching accounts.
        }
    }

    func requestAuthorizationForNotificationsPreference() async -> NotificationAuthorizationRequestResult {
        await CodexNotificationAuthorization.requestAuthorizationIfNeeded(center: center)
    }

    private func add(_ request: UNNotificationRequest) async throws {
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
}
