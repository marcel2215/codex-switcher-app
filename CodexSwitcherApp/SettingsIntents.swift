//
//  SettingsIntents.swift
//  Codex Switcher
//
//  Created by Marcel Kwiatkowski on 2026-04-10.
//

@preconcurrency import AppIntents
import Foundation
import UserNotifications

enum CodexIntentToggleState: String, AppEnum, CaseIterable {
    case on
    case off

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "State")
    static let caseDisplayRepresentations: [CodexIntentToggleState: DisplayRepresentation] = [
        .on: DisplayRepresentation(title: "On"),
        .off: DisplayRepresentation(title: "Off"),
    ]

    var isEnabled: Bool {
        self == .on
    }
}

#if os(macOS)
struct SetNotificationsIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Notifications"
    static let description = IntentDescription("Turns Codex Switcher account-switch notifications on or off.")
    static let supportedModes: IntentModes = .background

    @Parameter(
        title: "State",
        requestValueDialog: IntentDialog("Turn notifications on or off?")
    )
    var state: CodexIntentToggleState

    func perform() async throws -> some IntentResult & ReturnsValue<CodexIntentToggleState> & ProvidesDialog {
        if state.isEnabled {
            let settings = await UNUserNotificationCenter.current().notificationSettings()

            switch settings.authorizationStatus {
            case .authorized, .provisional:
                CodexSharedPreferences.userDefaults.set(
                    true,
                    forKey: CodexSharedPreferenceKey.accountSwitchNotificationsEnabled
                )
                CodexSharedPreferenceFeedback.postPreferencesDidChange()
                return .result(value: .on, dialog: IntentDialog("Notifications are on."))
            case .denied, .ephemeral, .notDetermined:
                CodexSharedPreferences.userDefaults.set(
                    false,
                    forKey: CodexSharedPreferenceKey.accountSwitchNotificationsEnabled
                )
                CodexSharedPreferenceFeedback.postPreferencesDidChange()
                return .result(
                    value: .off,
                    dialog: IntentDialog("Notifications stay off until you allow them in System Settings > Notifications.")
                )
            @unknown default:
                CodexSharedPreferences.userDefaults.set(
                    false,
                    forKey: CodexSharedPreferenceKey.accountSwitchNotificationsEnabled
                )
                CodexSharedPreferenceFeedback.postPreferencesDidChange()
                throw CodexSettingsIntentError.notificationsUpdateFailed(
                    "macOS returned an unknown notification authorization state."
                )
            }
        }

        CodexSharedPreferences.userDefaults.set(
            false,
            forKey: CodexSharedPreferenceKey.accountSwitchNotificationsEnabled
        )
        CodexSharedPreferenceFeedback.postPreferencesDidChange()
        return .result(value: .off, dialog: IntentDialog("Notifications are off."))
    }
}
#endif

#if os(macOS)
struct SetMenuBarVisibilityIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Menu Bar Visibility"
    static let description = IntentDescription("Turns Codex Switcher's menu-bar item on or off.")
    static let supportedModes: IntentModes = .background

    @Parameter(
        title: "State",
        requestValueDialog: IntentDialog("Turn Show in Menu Bar on or off?")
    )
    var state: CodexIntentToggleState

    func perform() async throws -> some IntentResult & ReturnsValue<CodexIntentToggleState> & ProvidesDialog {
        let wasEnabled = CodexSharedPreferences.showMenuBarExtra
        let isEnabled = state.isEnabled

        CodexSharedPreferences.userDefaults.set(isEnabled, forKey: CodexSharedPreferenceKey.showMenuBarExtra)
        CodexSharedPreferenceFeedback.postPreferencesDidChange()

        if wasEnabled == isEnabled {
            return .result(
                value: state,
                dialog: IntentDialog(isEnabled ? "Show in Menu Bar is already on." : "Show in Menu Bar is already off.")
            )
        }

        return .result(
            value: state,
            dialog: IntentDialog(isEnabled ? "Show in Menu Bar is on." : "Show in Menu Bar is off.")
        )
    }
}

struct SetLaunchAtLoginIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Launch at Login"
    static let description = IntentDescription("Turns Codex Switcher's Launch at Login setting on or off.")
    static let supportedModes: IntentModes = .background

    @Parameter(
        title: "State",
        requestValueDialog: IntentDialog("Turn Launch at Login on or off?")
    )
    var state: CodexIntentToggleState

    func perform() async throws -> some IntentResult & ReturnsValue<CodexIntentToggleState> & ProvidesDialog {
        let targetState = state.isEnabled
        let currentState = CodexSharedLaunchAtLoginService.currentState()

        if currentState.isEnabled == targetState && (!targetState || currentState.requiresApproval == false) {
            return .result(
                value: state,
                dialog: IntentDialog(targetState ? "Launch at Login is already on." : "Launch at Login is already off.")
            )
        }

        do {
            let updatedState = try CodexSharedLaunchAtLoginService.setEnabled(targetState)
            CodexSharedPreferenceFeedback.postPreferencesDidChange()

            if updatedState.isEnabled && updatedState.requiresApproval {
                return .result(
                    value: .on,
                    dialog: IntentDialog(
                        "Launch at Login is on, but macOS still requires approval in System Settings > General > Login Items."
                    )
                )
            }

            return .result(
                value: updatedState.isEnabled ? .on : .off,
                dialog: IntentDialog(updatedState.isEnabled ? "Launch at Login is on." : "Launch at Login is off.")
            )
        } catch {
            throw CodexSettingsIntentError.launchAtLoginUpdateFailed(
                CodexSharedLaunchAtLoginService.userFacingMessage(for: error)
            )
        }
    }
}
#endif

struct SetAutomaticSwitchAccountIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Automatically Switch Accounts"
    static let description = IntentDescription("Turns Codex Switcher's automatic account switching on or off.")
    static let supportedModes: IntentModes = .background

    @Parameter(
        title: "State",
        requestValueDialog: IntentDialog("Turn the Automatically Switch Accounts setting on or off?")
    )
    var state: CodexIntentToggleState

    func perform() async throws -> some IntentResult & ReturnsValue<CodexIntentToggleState> & ProvidesDialog {
        let wasEnabled = CodexSharedPreferences.autopilotEnabled
        let isEnabled = state.isEnabled

        CodexSharedPreferences.userDefaults.set(isEnabled, forKey: CodexSharedPreferenceKey.autopilotEnabled)
        CodexSharedPreferenceFeedback.postPreferencesDidChange()

        if wasEnabled == isEnabled {
            return .result(
                value: state,
                dialog: IntentDialog(
                    isEnabled
                        ? "The Automatically Switch Accounts setting is already on."
                        : "The Automatically Switch Accounts setting is already off."
                )
            )
        }

        return .result(
            value: state,
            dialog: IntentDialog(
                isEnabled
                    ? "The Automatically Switch Accounts setting is on."
                    : "The Automatically Switch Accounts setting is off."
            )
        )
    }
}

private enum CodexSettingsIntentError: LocalizedError {
    case notificationsUpdateFailed(String)
    case launchAtLoginUpdateFailed(String)

    var errorDescription: String? {
        switch self {
        case let .notificationsUpdateFailed(message),
             let .launchAtLoginUpdateFailed(message):
            message
        }
    }
}
