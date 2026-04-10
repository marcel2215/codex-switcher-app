//
//  AccountSwitchNotificationManager.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-07.
//

import Foundation
import UserNotifications

enum NotificationAuthorizationRequestResult: Equatable {
    case enabled
    case denied
    case failed(String)
}

@MainActor
protocol AccountSwitchNotifying: AnyObject {
    func postSwitchNotification(for accountName: String, kind: CodexSwitchNotificationKind) async
    func requestAuthorizationForNotificationsPreference() async -> NotificationAuthorizationRequestResult
}

@MainActor
final class AccountSwitchNotificationManager: NSObject, AccountSwitchNotifying {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
        self.center.delegate = self
    }

    func postSwitchNotification(for accountName: String, kind: CodexSwitchNotificationKind) async {
        guard CodexSharedPreferences.notificationsEnabled else {
            return
        }

        guard let content = CodexSharedSwitchNotificationContent.makeContent(
            accountName: accountName,
            kind: kind
        ) else {
            return
        }

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
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
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return .enabled
        case .denied, .ephemeral:
            return .denied
        case .notDetermined:
            do {
                let isGranted = try await center.requestAuthorization(options: [.alert])
                return isGranted ? .enabled : .denied
            } catch {
                return .failed(error.localizedDescription)
            }
        @unknown default:
            return .failed("macOS returned an unknown notification authorization state.")
        }
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

extension AccountSwitchNotificationManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner])
    }
}
