//
//  CodexSharedPreferences.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-10.
//

import Foundation

enum CodexSharedPreferenceKey {
    nonisolated static let notificationsEnabled = "notificationsEnabled"
    nonisolated static let autopilotEnabled = "autopilotEnabled"
}

enum CodexSharedPreferenceDefaults {
    nonisolated static let notificationsEnabled = false
    nonisolated static let autopilotEnabled = false
}

enum CodexSharedPreferences {
    /// Use the App Group defaults so the main app, widgets, and App Intents all
    /// read the same user preference. Fall back to standard defaults in tests
    /// or unsigned builds where the shared suite might be unavailable.
    nonisolated static var userDefaults: UserDefaults {
        UserDefaults(suiteName: CodexSharedAppGroup.identifier) ?? .standard
    }

    nonisolated static var notificationsEnabled: Bool {
        guard userDefaults.object(forKey: CodexSharedPreferenceKey.notificationsEnabled) != nil else {
            return CodexSharedPreferenceDefaults.notificationsEnabled
        }

        return userDefaults.bool(forKey: CodexSharedPreferenceKey.notificationsEnabled)
    }

    nonisolated static var autopilotEnabled: Bool {
        guard userDefaults.object(forKey: CodexSharedPreferenceKey.autopilotEnabled) != nil else {
            return CodexSharedPreferenceDefaults.autopilotEnabled
        }

        return userDefaults.bool(forKey: CodexSharedPreferenceKey.autopilotEnabled)
    }
}
