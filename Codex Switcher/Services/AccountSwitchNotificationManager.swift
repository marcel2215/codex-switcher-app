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
    func postSwitchNotification(for accountName: String) async
}

@MainActor
final class AccountSwitchNotificationManager: NSObject, AccountSwitchNotifying {
    private let center: UNUserNotificationCenter
    private var hasRequestedAuthorization = false

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
        self.center.delegate = self
    }

    func postSwitchNotification(for accountName: String) async {
        await requestAuthorizationIfNeeded()

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Account Switched"
        content.body = "Now using \"\(accountName)\"."
        content.sound = nil
        content.interruptionLevel = .active
        content.relevanceScore = 0

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

    private func requestAuthorizationIfNeeded() async {
        guard !hasRequestedAuthorization else {
            return
        }

        hasRequestedAuthorization = true

        do {
            _ = try await center.requestAuthorization(options: [.alert])
        } catch {
            // The app will continue to function without notifications.
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
