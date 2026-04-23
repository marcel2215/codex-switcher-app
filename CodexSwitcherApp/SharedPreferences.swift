//
//  SharedPreferences.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-10.
//

import Foundation

enum CodexSharedPreferenceKey {
    nonisolated static let notificationsEnabled = "notificationsEnabled"
    nonisolated static let accountSwitchNotificationsEnabled = "accountSwitchNotificationsEnabled"
    nonisolated static let rateLimitResetNotificationsEnabled = "rateLimitResetNotificationsEnabled"
    nonisolated static let fiveHourResetNotificationsEnabled = "fiveHourResetNotificationsEnabled"
    nonisolated static let sevenDayResetNotificationsEnabled = "sevenDayResetNotificationsEnabled"
    nonisolated static let autopilotEnabled = "autopilotEnabled"
    nonisolated static let showMenuBarExtra = "showMenuBarExtra"
}

enum CodexSharedPreferenceDefaults {
    nonisolated static let notificationsEnabled = false
    nonisolated static let accountSwitchNotificationsEnabled = false
    nonisolated static let rateLimitResetNotificationsEnabled = false
    nonisolated static let fiveHourResetNotificationsEnabled = false
    nonisolated static let sevenDayResetNotificationsEnabled = false
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
        accountSwitchNotificationsEnabled
    }

    nonisolated static var accountSwitchNotificationsEnabled: Bool {
        if userDefaults.object(forKey: CodexSharedPreferenceKey.accountSwitchNotificationsEnabled) != nil {
            return userDefaults.bool(forKey: CodexSharedPreferenceKey.accountSwitchNotificationsEnabled)
        }

        if userDefaults.object(forKey: CodexSharedPreferenceKey.notificationsEnabled) != nil {
            return userDefaults.bool(forKey: CodexSharedPreferenceKey.notificationsEnabled)
        }

        return CodexSharedPreferenceDefaults.accountSwitchNotificationsEnabled
    }

    nonisolated static var rateLimitResetNotificationsEnabled: Bool {
        boolValue(
            forKey: CodexSharedPreferenceKey.rateLimitResetNotificationsEnabled,
            defaultValue: CodexSharedPreferenceDefaults.rateLimitResetNotificationsEnabled
        )
    }

    nonisolated static var fiveHourResetNotificationsEnabled: Bool {
        boolValue(
            forKey: CodexSharedPreferenceKey.fiveHourResetNotificationsEnabled,
            defaultValue: CodexSharedPreferenceDefaults.fiveHourResetNotificationsEnabled
        )
    }

    nonisolated static var sevenDayResetNotificationsEnabled: Bool {
        boolValue(
            forKey: CodexSharedPreferenceKey.sevenDayResetNotificationsEnabled,
            defaultValue: CodexSharedPreferenceDefaults.sevenDayResetNotificationsEnabled
        )
    }

    nonisolated static var hasAnyRateLimitResetNotificationsEnabled: Bool {
        fiveHourResetNotificationsEnabled || sevenDayResetNotificationsEnabled
    }

    nonisolated static var autopilotEnabled: Bool {
        boolValue(
            forKey: CodexSharedPreferenceKey.autopilotEnabled,
            defaultValue: CodexSharedPreferenceDefaults.autopilotEnabled
        )
    }

    nonisolated static var showMenuBarExtra: Bool {
        boolValue(
            forKey: CodexSharedPreferenceKey.showMenuBarExtra,
            defaultValue: CodexSharedPreferenceDefaults.showMenuBarExtra
        )
    }

    nonisolated static func migrateLegacyPreferencesIfNeeded(
        legacyUserDefaults: UserDefaults = .standard
    ) {
        migrateLegacyMenuBarPreferenceIfNeeded(legacyUserDefaults: legacyUserDefaults)
        migrateLegacyNotificationPreferenceIfNeeded()
        migrateLegacyRateLimitResetPreferenceIfNeeded()
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

    /// Older builds stored all notification behavior behind one shared flag.
    /// Preserve that choice as the new account-switch notification toggle on
    /// first launch after the split settings UI ships.
    private nonisolated static func migrateLegacyNotificationPreferenceIfNeeded() {
        guard
            userDefaults.object(forKey: CodexSharedPreferenceKey.accountSwitchNotificationsEnabled) == nil,
            userDefaults.object(forKey: CodexSharedPreferenceKey.notificationsEnabled) != nil
        else {
            return
        }

        userDefaults.set(
            userDefaults.bool(forKey: CodexSharedPreferenceKey.notificationsEnabled),
            forKey: CodexSharedPreferenceKey.accountSwitchNotificationsEnabled
        )
    }

    /// The first reset-notification version used a single master toggle plus
    /// hidden per-window defaults. Seed any still-missing 5h/7d toggles from
    /// that master value before the UI switches to direct per-window controls.
    private nonisolated static func migrateLegacyRateLimitResetPreferenceIfNeeded() {
        guard userDefaults.object(forKey: CodexSharedPreferenceKey.rateLimitResetNotificationsEnabled) != nil else {
            return
        }

        let legacyValue = userDefaults.bool(forKey: CodexSharedPreferenceKey.rateLimitResetNotificationsEnabled)

        if userDefaults.object(forKey: CodexSharedPreferenceKey.fiveHourResetNotificationsEnabled) == nil {
            userDefaults.set(legacyValue, forKey: CodexSharedPreferenceKey.fiveHourResetNotificationsEnabled)
        }

        if userDefaults.object(forKey: CodexSharedPreferenceKey.sevenDayResetNotificationsEnabled) == nil {
            userDefaults.set(legacyValue, forKey: CodexSharedPreferenceKey.sevenDayResetNotificationsEnabled)
        }
    }

    private nonisolated static func boolValue(
        forKey key: String,
        defaultValue: Bool
    ) -> Bool {
        guard userDefaults.object(forKey: key) != nil else {
            return defaultValue
        }

        return userDefaults.bool(forKey: key)
    }
}
