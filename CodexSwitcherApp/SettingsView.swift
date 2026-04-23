//
//  SettingsView.swift
//  Codex Switcher
//
//  Created by Marcel Kwiatkowski on 2026-04-11.
//

import SwiftUI
import SwiftData
import UserNotifications
import UIKit

struct IOSSettingsView: View {
    private enum NotificationPreferenceKind {
        case fiveHourReset
        case sevenDayReset
    }

    private enum DangerZoneAction: String, Identifiable {
        case resetSettings
        case removeAllAccounts

        var id: String { rawValue }

        var title: String {
            switch self {
            case .resetSettings:
                "Reset Settings"
            case .removeAllAccounts:
                "Remove All Accounts"
            }
        }

        var message: String {
            switch self {
            case .resetSettings:
                "Reset notification preferences on this iPhone?"
            case .removeAllAccounts:
                "Remove every account from this iPhone? You can add them again later."
            }
        }

        var confirmationTitle: String {
            switch self {
            case .resetSettings:
                "Reset"
            case .removeAllAccounts:
                "Remove All"
            }
        }
    }

    private enum PresentedSettingsAlert: Identifiable {
        case error(title: String, message: String)

        var id: String {
            switch self {
            case let .error(title, message):
                "error-\(title)-\(message)"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var accounts: [StoredAccount]
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
    @State private var presentedDangerZoneAction: DangerZoneAction?
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

                Link(destination: AppSupportLink.websiteURL) {
                    Label("Visit Our Website", systemImage: "globe")
                }

                Link(destination: AppSupportLink.termsOfServiceURL) {
                    Label("Terms of Service", systemImage: "doc.text")
                }

                Link(destination: AppSupportLink.privacyPolicyURL) {
                    Label("Privacy Policy", systemImage: "hand.raised")
                }

                Link(destination: AppSupportLink.sourceCodeURL) {
                    Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                }

                if let applicationSettingsURL {
                    Link(destination: applicationSettingsURL) {
                        Label("More Settings", systemImage: "ellipsis.circle")
                    }
                }
            }

            Section("Danger Zone") {
                Button(role: .destructive) {
                    presentedDangerZoneAction = .resetSettings
                } label: {
                    dangerZoneLabel(
                        "Reset Settings",
                        systemImage: "arrow.counterclockwise",
                        isEnabled: isResetSettingsEnabled
                    )
                }
                .buttonStyle(.plain)
                .disabled(!isResetSettingsEnabled)

                Button(role: .destructive) {
                    presentedDangerZoneAction = .removeAllAccounts
                } label: {
                    dangerZoneLabel(
                        "Remove All Accounts",
                        systemImage: "trash",
                        isEnabled: hasSavedAccounts
                    )
                }
                .buttonStyle(.plain)
                .disabled(!hasSavedAccounts)
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
            switch alert {
            case let .error(title, message):
                Alert(
                    title: Text(title),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
        .confirmationDialog(
            presentedDangerZoneAction?.title ?? "",
            isPresented: dangerZoneDialogIsPresented,
            titleVisibility: .visible,
            presenting: presentedDangerZoneAction
        ) { action in
            Button(action.confirmationTitle, role: .destructive) {
                performDangerZoneAction(action)
            }
        } message: { action in
            Text(action.message)
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

    private var applicationSettingsURL: URL? {
        URL(string: UIApplication.openSettingsURLString)
    }

    private var hasSavedAccounts: Bool {
        !accounts.isEmpty
    }

    private var isResetSettingsEnabled: Bool {
        fiveHourResetNotificationsEnabled != CodexSharedPreferenceDefaults.fiveHourResetNotificationsEnabled
            || sevenDayResetNotificationsEnabled != CodexSharedPreferenceDefaults.sevenDayResetNotificationsEnabled
    }

    private var dangerZoneDialogIsPresented: Binding<Bool> {
        Binding(
            get: {
                presentedDangerZoneAction != nil
            },
            set: { isPresented in
                if !isPresented {
                    presentedDangerZoneAction = nil
                }
            }
        )
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
                presentedSettingsAlert = .error(
                    title: "Notifications Disabled",
                    message: "Codex Switcher can only show notifications after you allow them in Settings > Notifications."
                )
            case let .failed(message):
                setNotificationPreference(kind, isEnabled: false)
                presentedSettingsAlert = .error(
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

    private func dangerZoneLabel(
        _ title: String,
        systemImage: String,
        isEnabled: Bool
    ) -> some View {
        Label(title, systemImage: systemImage)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(isEnabled ? .red : .secondary)
            .contentShape(Rectangle())
    }

    private func performDangerZoneAction(_ action: DangerZoneAction) {
        switch action {
        case .resetSettings:
            resetSettingsToDefaults()
        case .removeAllAccounts:
            removeAllAccounts()
        }

        presentedDangerZoneAction = nil
    }

    private func resetSettingsToDefaults() {
        fiveHourResetNotificationsEnabled = CodexSharedPreferenceDefaults.fiveHourResetNotificationsEnabled
        sevenDayResetNotificationsEnabled = CodexSharedPreferenceDefaults.sevenDayResetNotificationsEnabled
        synchronizeResetNotifications()
    }

    private func removeAllAccounts() {
        do {
            try StoredAccountMutations.removeAll(accounts, in: modelContext)
        } catch {
            presentedSettingsAlert = .error(
                title: "Couldn't Remove Accounts",
                message: error.localizedDescription
            )
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
