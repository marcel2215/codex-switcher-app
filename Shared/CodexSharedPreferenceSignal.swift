//
//  CodexSharedPreferenceSignal.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-10.
//

import Foundation

enum CodexSharedPreferenceFeedback {
    nonisolated static let didChangePreferencesNotification = Notification.Name(
        "com.marcel2215.codexswitcher.didChangePreferences"
    )

    /// Broadcast preference mutations that can affect already-running app
    /// behavior, such as Autopilot residency and menu-bar presentation.
    nonisolated static func postPreferencesDidChange() {
#if os(macOS)
        DistributedNotificationCenter.default().post(
            name: didChangePreferencesNotification,
            object: nil
        )
#else
        NotificationCenter.default.post(name: didChangePreferencesNotification, object: nil)
#endif
    }
}
