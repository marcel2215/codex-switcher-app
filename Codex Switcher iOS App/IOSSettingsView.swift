//
//  IOSSettingsView.swift
//  Codex Switcher iOS App
//
//  Created by Codex on 2026-04-11.
//

import SwiftUI
import UserNotifications

struct IOSSettingsView: View {
    private enum NotificationPreferenceKind {
        case fiveHourReset
        case sevenDayReset
    }

    private struct PresentedSettingsAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(
        CodexSharedPreferenceKey.fiveHourResetNotificationsEnabled,
        store: CodexSharedPreferences.userDefaults
    ) private var fiveHourResetNotificationsEnabled = CodexSharedPreferenceDefaults.fiveHourResetNotificationsEnabled
    @AppStorage(
        CodexSharedPreferenceKey.sevenDayResetNotificationsEnabled,
        store: CodexSharedPreferences.userDefaults
    ) private var sevenDayResetNotificationsEnabled = CodexSharedPreferenceDefaults.sevenDayResetNotificationsEnabled
    @State private var isUpdatingNotificationPreferences = false
    @State private var presentedSettingsAlert: PresentedSettingsAlert?
    @State private var notificationAuthorizationStatus: UNAuthorizationStatus?

    var body: some View {
        Form {
            Section {
                Toggle("5-Hour Limit Reset", isOn: fiveHourResetNotificationsBinding)
                    .disabled(isUpdatingNotificationPreferences)

                Toggle("7-Day Limit Reset", isOn: sevenDayResetNotificationsBinding)
                    .disabled(isUpdatingNotificationPreferences)
            } header: {
                Text("Notifications")
            } footer: {
                notificationSettingsFooter
            }

            Section("About") {
                LabeledContent("Version") {
                    Text(AppAboutInfo.current.formattedVersion)
                }
            }

            Section("Actions") {
                Link(destination: AppSupportLink.contactURL) {
                    Label("Contact Us", systemImage: "envelope")
                }

                Link(destination: AppSupportLink.privacyPolicyURL) {
                    Label("Privacy Policy", systemImage: "hand.raised")
                }

                Link(destination: AppSupportLink.sourceCodeURL) {
                    Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }
        }
        .navigationTitle("Settings")
        .task {
            await refreshNotificationAuthorizationStatus()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else {
                return
            }

            Task {
                await refreshNotificationAuthorizationStatus()
            }
        }
        .alert(item: $presentedSettingsAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Close Settings")
            }
        }
    }

    @ViewBuilder
    private var notificationSettingsFooter: some View {
        if let notificationAuthorizationStatus,
           CodexNotificationSettingsLink.shouldShowDisabledFooter(for: notificationAuthorizationStatus),
           let destination = CodexNotificationSettingsLink.sectionFooterURL() {
            Text(.init("Notifications are disabled in system settings. [Change](\(destination.absoluteString))"))
        }
    }

    private var fiveHourResetNotificationsBinding: Binding<Bool> {
        Binding(
            get: {
                fiveHourResetNotificationsEnabled
            },
            set: { newValue in
                updateNotificationPreference(.fiveHourReset, isEnabled: newValue)
            }
        )
    }

    private var sevenDayResetNotificationsBinding: Binding<Bool> {
        Binding(
            get: {
                sevenDayResetNotificationsEnabled
            },
            set: { newValue in
                updateNotificationPreference(.sevenDayReset, isEnabled: newValue)
            }
        )
    }

    private func updateNotificationPreference(
        _ kind: NotificationPreferenceKind,
        isEnabled: Bool
    ) {
        guard !isUpdatingNotificationPreferences else {
            return
        }

        guard isEnabled else {
            setNotificationPreference(kind, isEnabled: false)
            return
        }

        setNotificationPreference(kind, isEnabled: true)
        isUpdatingNotificationPreferences = true

        Task { @MainActor in
            let authorizationResult = await CodexNotificationAuthorization.requestAuthorizationIfNeeded()
            isUpdatingNotificationPreferences = false
            await refreshNotificationAuthorizationStatus()

            switch authorizationResult {
            case .enabled:
                setNotificationPreference(kind, isEnabled: true)
            case .denied:
                setNotificationPreference(kind, isEnabled: false)
                presentedSettingsAlert = PresentedSettingsAlert(
                    title: "Notifications Disabled",
                    message: "Codex Switcher can only show notifications after you allow them in Settings > Notifications."
                )
            case let .failed(message):
                setNotificationPreference(kind, isEnabled: false)
                presentedSettingsAlert = PresentedSettingsAlert(
                    title: "Couldn't Enable Notifications",
                    message: message
                )
            }
        }
    }

    private func setNotificationPreference(
        _ kind: NotificationPreferenceKind,
        isEnabled: Bool
    ) {
        switch kind {
        case .fiveHourReset:
            fiveHourResetNotificationsEnabled = isEnabled
            synchronizeResetNotifications()
        case .sevenDayReset:
            sevenDayResetNotificationsEnabled = isEnabled
            synchronizeResetNotifications()
        }
    }

    private func synchronizeResetNotifications() {
        CodexSharedPreferenceFeedback.postPreferencesDidChange()
        Task {
            await RateLimitResetNotificationScheduler.shared.synchronizeWithStoredState()
            await refreshNotificationAuthorizationStatus()
        }
    }

    private func refreshNotificationAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationAuthorizationStatus = settings.authorizationStatus
    }
}
