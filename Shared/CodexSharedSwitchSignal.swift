//
//  CodexSharedSwitchSignal.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-09.
//

import Foundation
import UserNotifications

struct CodexSharedSwitchSignal: Sendable, Equatable {
    let identityKey: String
    let accountName: String
}

enum CodexSharedSwitchFeedback {
    nonisolated private static let identityKeyUserInfoKey = "identityKey"
    nonisolated private static let accountNameUserInfoKey = "accountName"

    nonisolated static let didSwitchAccountNotification = Notification.Name(
        "com.marcel2215.codexswitcher.didSwitchAccount"
    )

    /// Broadcast the completed account switch so any already-running app
    /// instance can refresh immediately instead of waiting for file watching or
    /// a future launch/activation.
    nonisolated static func postSwitchSignal(identityKey: String, accountName: String) {
        let trimmedIdentityKey = identityKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAccountName = accountName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedIdentityKey.isEmpty, !trimmedAccountName.isEmpty else {
            return
        }

#if os(macOS)
        DistributedNotificationCenter.default().post(
            name: didSwitchAccountNotification,
            object: nil,
            userInfo: [
                identityKeyUserInfoKey: trimmedIdentityKey,
                accountNameUserInfoKey: trimmedAccountName,
            ]
        )
#else
        NotificationCenter.default.post(
            name: didSwitchAccountNotification,
            object: nil,
            userInfo: [
                identityKeyUserInfoKey: trimmedIdentityKey,
                accountNameUserInfoKey: trimmedAccountName,
            ]
        )
#endif
    }

    nonisolated static func signal(from notification: Notification) -> CodexSharedSwitchSignal? {
        guard
            let userInfo = notification.userInfo,
            let identityKey = userInfo[identityKeyUserInfoKey] as? String,
            let accountName = userInfo[accountNameUserInfoKey] as? String
        else {
            return nil
        }

        let trimmedIdentityKey = identityKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAccountName = accountName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedIdentityKey.isEmpty, !trimmedAccountName.isEmpty else {
            return nil
        }

        return CodexSharedSwitchSignal(
            identityKey: trimmedIdentityKey,
            accountName: trimmedAccountName
        )
    }

    /// App Intents can run when the main app is hidden or not running. Use a
    /// direct local notification here so the user still gets a confirmation
    /// banner even when the app's in-process notification delegate is not the
    /// code path completing the switch. Respect the shared notification
    /// preference instead of prompting here, because the explicit settings
    /// toggle is responsible for requesting permission.
    static func postLocalSwitchNotificationIfAuthorized(
        accountName: String,
        kind: CodexSwitchNotificationKind = .backgroundConfirmation
    ) async {
        guard CodexSharedPreferences.accountSwitchNotificationsEnabled else {
            return
        }

        guard let content = CodexSharedSwitchNotificationContent.makeContent(
            accountName: accountName,
            kind: kind
        ) else {
            return
        }

        let center = UNUserNotificationCenter.current()
        let finalSettings = await center.notificationSettings()
        guard CodexNotificationAuthorization.isDeliveryAuthorized(finalSettings.authorizationStatus) else {
            return
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        )

        do {
            try await addNotificationRequest(request, to: center)
        } catch {
            // The account switch already completed successfully; failing to
            // show a banner should never roll that back.
        }
    }

    private static func addNotificationRequest(
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
}
