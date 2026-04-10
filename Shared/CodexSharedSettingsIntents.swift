//
//  CodexSharedSettingsIntents.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-10.
//

import AppIntents
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

struct SetNotificationsIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Notifications"
    static let description = IntentDescription("Turns Codex Switcher account-switch notifications on or off.")

    @Parameter(title: "State")
    var state: CodexIntentToggleState

    static var parameterSummary: some ParameterSummary {
        Summary("Turn notifications \(\.$state)")
    }

    nonisolated func perform() async throws -> some IntentResult & ProvidesDialog {
        if state.isEnabled {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()

            switch settings.authorizationStatus {
            case .authorized, .provisional:
                CodexSharedPreferences.userDefaults.set(true, forKey: CodexSharedPreferenceKey.notificationsEnabled)
                CodexSharedPreferenceFeedback.postPreferencesDidChange()
                return .result(dialog: IntentDialog("Notifications are on."))
            case .denied, .ephemeral:
                CodexSharedPreferences.userDefaults.set(false, forKey: CodexSharedPreferenceKey.notificationsEnabled)
                CodexSharedPreferenceFeedback.postPreferencesDidChange()
                return .result(
                    dialog: IntentDialog("Notifications stay off until you allow them in System Settings > Notifications.")
                )
            case .notDetermined:
                do {
                    let granted = try await center.requestAuthorization(options: [.alert])
                    CodexSharedPreferences.userDefaults.set(
                        granted,
                        forKey: CodexSharedPreferenceKey.notificationsEnabled
                    )
                    CodexSharedPreferenceFeedback.postPreferencesDidChange()
                    return .result(
                        dialog: IntentDialog(
                            granted
                                ? "Notifications are on."
                                : "Notifications stay off until you allow them in System Settings > Notifications."
                        )
                    )
                } catch {
                    CodexSharedPreferences.userDefaults.set(false, forKey: CodexSharedPreferenceKey.notificationsEnabled)
                    CodexSharedPreferenceFeedback.postPreferencesDidChange()
                    throw CodexSettingsIntentError.notificationsUpdateFailed(error.localizedDescription)
                }
            @unknown default:
                CodexSharedPreferences.userDefaults.set(false, forKey: CodexSharedPreferenceKey.notificationsEnabled)
                CodexSharedPreferenceFeedback.postPreferencesDidChange()
                throw CodexSettingsIntentError.notificationsUpdateFailed(
                    "macOS returned an unknown notification authorization state."
                )
            }
        }

        CodexSharedPreferences.userDefaults.set(false, forKey: CodexSharedPreferenceKey.notificationsEnabled)
        CodexSharedPreferenceFeedback.postPreferencesDidChange()
        return .result(dialog: IntentDialog("Notifications are off."))
    }
}

struct SetMenuBarVisibilityIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Menu Bar Visibility"
    static let description = IntentDescription("Turns Codex Switcher's menu-bar item on or off.")

    @Parameter(title: "State")
    var state: CodexIntentToggleState

    static var parameterSummary: some ParameterSummary {
        Summary("Turn Show in Menu Bar \(\.$state)")
    }

    nonisolated func perform() async throws -> some IntentResult & ProvidesDialog {
        let wasEnabled = CodexSharedPreferences.showMenuBarExtra
        let isEnabled = state.isEnabled

        CodexSharedPreferences.userDefaults.set(isEnabled, forKey: CodexSharedPreferenceKey.showMenuBarExtra)
        CodexSharedPreferenceFeedback.postPreferencesDidChange()

        if wasEnabled == isEnabled {
            return .result(
                dialog: IntentDialog(isEnabled ? "Show in Menu Bar is already on." : "Show in Menu Bar is already off.")
            )
        }

        return .result(
            dialog: IntentDialog(isEnabled ? "Show in Menu Bar is on." : "Show in Menu Bar is off.")
        )
    }
}

struct SetLaunchAtLoginIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Launch at Login"
    static let description = IntentDescription("Turns Codex Switcher's Launch at Login setting on or off.")

    @Parameter(title: "State")
    var state: CodexIntentToggleState

    static var parameterSummary: some ParameterSummary {
        Summary("Turn Launch at Login \(\.$state)")
    }

    nonisolated func perform() async throws -> some IntentResult & ProvidesDialog {
        let targetState = state.isEnabled
        let currentState = CodexSharedLaunchAtLoginService.currentState()

        if currentState.isEnabled == targetState && (!targetState || currentState.requiresApproval == false) {
            return .result(
                dialog: IntentDialog(targetState ? "Launch at Login is already on." : "Launch at Login is already off.")
            )
        }

        do {
            let updatedState = try CodexSharedLaunchAtLoginService.setEnabled(targetState)
            CodexSharedPreferenceFeedback.postPreferencesDidChange()

            if updatedState.isEnabled && updatedState.requiresApproval {
                return .result(
                    dialog: IntentDialog(
                        "Launch at Login is on, but macOS still requires approval in System Settings > General > Login Items."
                    )
                )
            }

            return .result(
                dialog: IntentDialog(updatedState.isEnabled ? "Launch at Login is on." : "Launch at Login is off.")
            )
        } catch {
            throw CodexSettingsIntentError.launchAtLoginUpdateFailed(
                CodexSharedLaunchAtLoginService.userFacingMessage(for: error)
            )
        }
    }
}

struct SetAutomaticSwitchAccountIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Automatically Switch Account"
    static let description = IntentDescription("Turns Codex Switcher's automatic account switching on or off.")

    @Parameter(title: "State")
    var state: CodexIntentToggleState

    static var parameterSummary: some ParameterSummary {
        Summary("Turn Automatically Switch Account \(\.$state)")
    }

    nonisolated func perform() async throws -> some IntentResult & ProvidesDialog {
        let wasEnabled = CodexSharedPreferences.autopilotEnabled
        let isEnabled = state.isEnabled

        CodexSharedPreferences.userDefaults.set(isEnabled, forKey: CodexSharedPreferenceKey.autopilotEnabled)
        CodexSharedPreferenceFeedback.postPreferencesDidChange()

        if wasEnabled == isEnabled {
            return .result(
                dialog: IntentDialog(
                    isEnabled
                        ? "Automatically Switch Account is already on."
                        : "Automatically Switch Account is already off."
                )
            )
        }

        return .result(
            dialog: IntentDialog(
                isEnabled
                    ? "Automatically Switch Account is on."
                    : "Automatically Switch Account is off."
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
