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
    nonisolated static let showMenuBarExtra = "showMenuBarExtra"
}

enum CodexSharedPreferenceDefaults {
    nonisolated static let notificationsEnabled = false
    nonisolated static let autopilotEnabled = false
    nonisolated static let showMenuBarExtra = true
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

    nonisolated static var showMenuBarExtra: Bool {
        guard userDefaults.object(forKey: CodexSharedPreferenceKey.showMenuBarExtra) != nil else {
            return CodexSharedPreferenceDefaults.showMenuBarExtra
        }

        return userDefaults.bool(forKey: CodexSharedPreferenceKey.showMenuBarExtra)
    }

    /// The menu-bar preference originally lived in the app's standard defaults.
    /// Move it into the App Group suite once so App Intents and widgets can
    /// read and update the same value as the main app.
    nonisolated static func migrateLegacyMenuBarPreferenceIfNeeded(
        legacyUserDefaults: UserDefaults = .standard
    ) {
        guard userDefaults.object(forKey: CodexSharedPreferenceKey.showMenuBarExtra) == nil,
              legacyUserDefaults.object(forKey: CodexSharedPreferenceKey.showMenuBarExtra) != nil
        else {
            return
        }

        userDefaults.set(
            legacyUserDefaults.bool(forKey: CodexSharedPreferenceKey.showMenuBarExtra),
            forKey: CodexSharedPreferenceKey.showMenuBarExtra
        )
    }
}
