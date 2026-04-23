//
//  InAppNotificationSettingsSignal.swift
//  Codex Switcher
//
//  Created by Marcel Kwiatkowski on 2026-04-14.
//

import Foundation

enum CodexInAppNotificationSettingsSignal {
    nonisolated static let didRequestOpenNotificationSettings = Notification.Name(
        "com.marcel2215.codexswitcher.didRequestOpenNotificationSettings"
    )

    private nonisolated static let pendingRequestKey = "pendingInAppNotificationSettingsRequest"

    /// Persist the request locally so a cold launch from system notification
    /// settings can still open the app's own notification preferences after
    /// SwiftUI finishes creating the first scene.
    nonisolated static func requestOpenNotificationSettings(
        userDefaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default
    ) {
        userDefaults.set(true, forKey: pendingRequestKey)
        notificationCenter.post(name: didRequestOpenNotificationSettings, object: nil)
    }

    nonisolated static func consumePendingOpenNotificationSettingsRequest(
        userDefaults: UserDefaults = .standard
    ) -> Bool {
        guard userDefaults.bool(forKey: pendingRequestKey) else {
            return false
        }

        userDefaults.removeObject(forKey: pendingRequestKey)
        return true
    }
}
