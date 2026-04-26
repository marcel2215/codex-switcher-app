//
//  App.swift
//  Codex Switcher Mac App
//
//  Created by Marcel Kwiatkowski on 2026-04-06.
//

import SwiftUI
import SwiftData
import AppIntents
import UserNotifications

@main
struct CodexSwitcherApp: App {
    @AppStorage(
        CodexSharedPreferenceKey.accountSwitchNotificationsEnabled,
        store: CodexSharedPreferences.userDefaults
    ) private var accountSwitchNotificationsEnabled = CodexSharedPreferenceDefaults.accountSwitchNotificationsEnabled
    @AppStorage(
        CodexSharedPreferenceKey.fiveHourResetNotificationsEnabled,
        store: CodexSharedPreferences.userDefaults
    ) private var fiveHourResetNotificationsEnabled = CodexSharedPreferenceDefaults.fiveHourResetNotificationsEnabled
    @AppStorage(
        CodexSharedPreferenceKey.sevenDayResetNotificationsEnabled,
        store: CodexSharedPreferences.userDefaults
    ) private var sevenDayResetNotificationsEnabled = CodexSharedPreferenceDefaults.sevenDayResetNotificationsEnabled
    @AppStorage(
        CodexSharedPreferenceKey.autopilotEnabled,
        store: CodexSharedPreferences.userDefaults
    ) private var autopilotEnabled = CodexSharedPreferenceDefaults.autopilotEnabled
    @AppStorage(
        CodexSharedPreferenceKey.showMenuBarExtra,
        store: CodexSharedPreferences.userDefaults
    ) private var showMenuBarExtra = CodexSharedPreferenceDefaults.showMenuBarExtra
    @AppStorage(
        CodexSharedPreferenceKey.showNoneAccount,
        store: CodexSharedPreferences.userDefaults
    ) private var showNoneAccount = CodexSharedPreferenceDefaults.showNoneAccount
    @AppStorage(
        CodexSharedPreferenceKey.automaticallyAddAccounts,
        store: CodexSharedPreferences.userDefaults
    ) private var automaticallyAddAccounts = CodexSharedPreferenceDefaults.automaticallyAddAccounts
    @AppStorage(
        CodexSharedPreferenceKey.automaticallyRemoveAccounts,
        store: CodexSharedPreferences.userDefaults
    ) private var automaticallyRemoveAccounts = CodexSharedPreferenceDefaults.automaticallyRemoveAccounts
    @AppStorage(AppPreferenceKey.menuBarIconSystemName) private var persistedMenuBarIconSystemName = AppPreferenceDefaults.menuBarIconSystemName
    @AppStorage(AppPreferenceKey.sortCriterion) private var persistedSortCriterionRawValue = AppPreferenceDefaults.sortCriterionRawValue
    @AppStorage(AppPreferenceKey.sortDirection) private var persistedSortDirectionRawValue = AppPreferenceDefaults.sortDirectionRawValue
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var applicationDelegate
    @State private var controller: AppController
    @State private var sharedPreferenceObservationTask: Task<Void, Never>?

    private let sharedModelContainer: ModelContainer?
    private let storageRecoveryMessage: String?

    init() {
        CodexSharedPreferences.migrateLegacyPreferencesIfNeeded()
        CodexSharedContainerPreflight.logFailureIfNeeded()
        CodexSwitcherAppShortcuts.updateAppShortcutParameters()
        let bootstrap = AppBootstrap.make()
        self.sharedModelContainer = bootstrap.modelContainer
        self.storageRecoveryMessage = bootstrap.storageRecoveryMessage

        if !AppRuntimeEnvironment.isRunningUnitTests,
           let modelContainer = bootstrap.modelContainer {
            // Control Center can background-launch the app without creating a
            // visible scene first. Configure the controller eagerly so queued
            // app-owned commands are observed and drained even in that
            // headless launch path.
            bootstrap.controller.configure(
                modelContext: modelContainer.mainContext,
                undoManager: nil
            )
        }

        _controller = State(initialValue: bootstrap.controller)
    }

    var body: some Scene {
        mainWindowScene
        accountDetailsWindowScene
        settingsScene
        menuBarScene
    }

    @SceneBuilder
    private var mainWindowScene: some Scene {
        Window("Codex Switcher", id: "main") {
            rootContentView
                .task {
                    await performAppStartupTasksIfNeeded()
                }
        }
        .defaultSize(width: 620, height: 720)
        .commands {
            AccountsCommands(
                controller: controller,
                applicationDelegate: applicationDelegate,
                showsMenuBarExtra: showMenuBarExtra
            )
        }
    }

    @SceneBuilder
    private var accountDetailsWindowScene: some Scene {
        WindowGroup("Account Details", id: AccountDetailsWindowID.details, for: UUID.self) { accountID in
            accountDetailsWindowContent(accountID: accountID.wrappedValue)
                .task {
                    await performAppStartupTasksIfNeeded()
                }
        }
        .defaultSize(width: 500, height: 420)
    }

    @SceneBuilder
    private var settingsScene: some Scene {
        Settings {
            SettingsView(
                controller: controller,
                accountSwitchNotificationsEnabled: $accountSwitchNotificationsEnabled,
                fiveHourResetNotificationsEnabled: $fiveHourResetNotificationsEnabled,
                sevenDayResetNotificationsEnabled: $sevenDayResetNotificationsEnabled,
                autopilotEnabled: autopilotBinding,
                showNoneAccount: showNoneAccountBinding,
                automaticallyAddAccounts: $automaticallyAddAccounts,
                automaticallyRemoveAccounts: automaticallyRemoveAccountsBinding,
                showMenuBarExtra: showMenuBarExtraBinding,
                menuBarIcon: menuBarIconBinding,
                areAppPreferencesAtDefaults: areAppPreferencesAtDefaults,
                onResetSettings: resetStoredSettingsToDefaults
            )
            .frame(width: 520, height: 680)
            .task {
                await performAppStartupTasksIfNeeded()
            }
        }
    }

    @SceneBuilder
    private var menuBarScene: some Scene {
        // The menu bar extra remains available even when the main window is
        // closed. If SwiftData failed to initialize, keep the extra alive and
        // show a recovery surface instead of removing the system entry point.
        MenuBarExtra(
            "Codex Switcher",
            systemImage: menuBarIconBinding.wrappedValue.systemName,
            isInserted: showMenuBarExtraBinding
        ) {
            if let sharedModelContainer {
                SortPreferencePersistenceView(
                    controller: controller,
                    persistedSortCriterionRawValue: $persistedSortCriterionRawValue,
                    persistedSortDirectionRawValue: $persistedSortDirectionRawValue
                ) {
                    MenuBarAccountsView(controller: controller)
                        .modelContainer(sharedModelContainer)
                }
                    .task {
                        await performAppStartupTasksIfNeeded()
                    }
            } else {
                MenuBarStorageRecoveryView(
                    message: storageRecoveryMessage ?? "Codex Switcher couldn't open its local database."
                )
                .task {
                    await performAppStartupTasksIfNeeded()
                }
            }
        }
        .menuBarExtraStyle(.window)
        .defaultSize(width: 360, height: 820)
        .windowResizability(.contentSize)
    }

    private var showMenuBarExtraBinding: Binding<Bool> {
        Binding(
            get: {
                showMenuBarExtra
            },
            set: { newValue in
                showMenuBarExtra = newValue
                applicationDelegate.applyBackgroundResidency(
                    menuBarEnabled: newValue,
                    autopilotEnabled: autopilotEnabled
                )
            }
        )
    }

    private var autopilotBinding: Binding<Bool> {
        Binding(
            get: {
                autopilotEnabled
            },
            set: { newValue in
                autopilotEnabled = newValue
                controller.setAutopilotEnabled(newValue)
                applicationDelegate.applyBackgroundResidency(
                    menuBarEnabled: showMenuBarExtra,
                    autopilotEnabled: newValue
                )
            }
        )
    }

    private var showNoneAccountBinding: Binding<Bool> {
        Binding(
            get: {
                showNoneAccount
            },
            set: { newValue in
                showNoneAccount = newValue
                CodexSharedPreferenceFeedback.postPreferencesDidChange()
            }
        )
    }

    private var automaticallyRemoveAccountsBinding: Binding<Bool> {
        Binding(
            get: {
                automaticallyRemoveAccounts
            },
            set: { newValue in
                let wasEnabled = automaticallyRemoveAccounts
                automaticallyRemoveAccounts = newValue
                if newValue && !wasEnabled {
                    controller.removeUnavailableAccountsIfAutomaticRemoveEnabled()
                }
            }
        )
    }

    private var menuBarIconBinding: Binding<MenuBarIconOption> {
        Binding(
            get: {
                MenuBarIconOption.resolve(from: persistedMenuBarIconSystemName)
            },
            set: { newValue in
                persistedMenuBarIconSystemName = newValue.systemName
            }
        )
    }

    private func resetStoredSettingsToDefaults() {
        accountSwitchNotificationsEnabled = CodexSharedPreferenceDefaults.accountSwitchNotificationsEnabled
        fiveHourResetNotificationsEnabled = CodexSharedPreferenceDefaults.fiveHourResetNotificationsEnabled
        sevenDayResetNotificationsEnabled = CodexSharedPreferenceDefaults.sevenDayResetNotificationsEnabled
        autopilotBinding.wrappedValue = CodexSharedPreferenceDefaults.autopilotEnabled
        showNoneAccountBinding.wrappedValue = CodexSharedPreferenceDefaults.showNoneAccount
        automaticallyAddAccounts = CodexSharedPreferenceDefaults.automaticallyAddAccounts
        automaticallyRemoveAccounts = CodexSharedPreferenceDefaults.automaticallyRemoveAccounts
        showMenuBarExtraBinding.wrappedValue = CodexSharedPreferenceDefaults.showMenuBarExtra
        menuBarIconBinding.wrappedValue = MenuBarIconOption.defaultOption
        persistedSortCriterionRawValue = AppPreferenceDefaults.sortCriterionRawValue
        persistedSortDirectionRawValue = AppPreferenceDefaults.sortDirectionRawValue
        controller.restoreSortPreferences(
            sortCriterionRawValue: persistedSortCriterionRawValue,
            sortDirectionRawValue: persistedSortDirectionRawValue
        )
        CodexSharedPreferenceFeedback.postPreferencesDidChange()
        Task {
            await RateLimitResetNotificationScheduler.shared.synchronizeWithStoredState()
        }
    }

    private func configureControllerIfPossible() {
        let controller = controller
        applicationDelegate.configureDockAccounts(
            provider: { [weak controller] limit in
                controller?.dockAccounts(limit: limit) ?? []
            },
            onSelect: { [weak controller] accountID in
                controller?.login(accountID: accountID)
            }
        )

        guard let sharedModelContainer else {
            return
        }

        controller.configure(modelContext: sharedModelContainer.mainContext, undoManager: nil)
    }

    private func performAppStartupTasksIfNeeded() async {
        guard !AppRuntimeEnvironment.isRunningUnitTests else {
            return
        }

        configureControllerIfPossible()
        startSharedPreferenceObservationIfNeeded()
        applyRuntimePreferences()
        await controller.processPendingSharedCommands()
    }

    private var areAppPreferencesAtDefaults: Bool {
        accountSwitchNotificationsEnabled == CodexSharedPreferenceDefaults.accountSwitchNotificationsEnabled
            && fiveHourResetNotificationsEnabled == CodexSharedPreferenceDefaults.fiveHourResetNotificationsEnabled
            && sevenDayResetNotificationsEnabled == CodexSharedPreferenceDefaults.sevenDayResetNotificationsEnabled
            && autopilotEnabled == CodexSharedPreferenceDefaults.autopilotEnabled
            && showNoneAccount == CodexSharedPreferenceDefaults.showNoneAccount
            && automaticallyAddAccounts == CodexSharedPreferenceDefaults.automaticallyAddAccounts
            && automaticallyRemoveAccounts == CodexSharedPreferenceDefaults.automaticallyRemoveAccounts
            && showMenuBarExtra == CodexSharedPreferenceDefaults.showMenuBarExtra
            && persistedMenuBarIconSystemName == AppPreferenceDefaults.menuBarIconSystemName
            && persistedSortCriterionRawValue == AppPreferenceDefaults.sortCriterionRawValue
            && persistedSortDirectionRawValue == AppPreferenceDefaults.sortDirectionRawValue
    }

    private func applyRuntimePreferences() {
        controller.setAutopilotEnabled(autopilotEnabled)
        if automaticallyRemoveAccounts {
            controller.removeUnavailableAccountsIfAutomaticRemoveEnabled()
        }
        applicationDelegate.applyBackgroundResidency(
            menuBarEnabled: showMenuBarExtra,
            autopilotEnabled: autopilotEnabled
        )
    }

    private func startSharedPreferenceObservationIfNeeded() {
        guard sharedPreferenceObservationTask == nil else {
            return
        }

        sharedPreferenceObservationTask = Task { @MainActor in
            let notifications = DistributedNotificationCenter.default().notifications(
                named: CodexSharedPreferenceFeedback.didChangePreferencesNotification,
                object: nil
            )

            for await _ in notifications {
                synchronizeRuntimePreferencesFromSharedStore()
            }
        }
    }

    private func synchronizeRuntimePreferencesFromSharedStore() {
        accountSwitchNotificationsEnabled = CodexSharedPreferences.accountSwitchNotificationsEnabled
        fiveHourResetNotificationsEnabled = CodexSharedPreferences.fiveHourResetNotificationsEnabled
        sevenDayResetNotificationsEnabled = CodexSharedPreferences.sevenDayResetNotificationsEnabled
        autopilotEnabled = CodexSharedPreferences.autopilotEnabled
        showNoneAccount = CodexSharedPreferences.showNoneAccount
        automaticallyAddAccounts = CodexSharedPreferences.automaticallyAddAccounts
        automaticallyRemoveAccounts = CodexSharedPreferences.automaticallyRemoveAccounts
        showMenuBarExtra = CodexSharedPreferences.showMenuBarExtra
        applyRuntimePreferences()
    }

    @ViewBuilder
    private var rootContentView: some View {
        if let sharedModelContainer {
            SortPreferencePersistenceView(
                controller: controller,
                persistedSortCriterionRawValue: $persistedSortCriterionRawValue,
                persistedSortDirectionRawValue: $persistedSortDirectionRawValue
            ) {
                ContentView(controller: controller)
                    .modelContainer(sharedModelContainer)
            }
        } else {
            StorageRecoveryView(message: storageRecoveryMessage ?? "Codex Switcher couldn't open its local database.")
        }
    }

    @ViewBuilder
    private func accountDetailsWindowContent(accountID: UUID?) -> some View {
        if let sharedModelContainer {
            AccountDetailsWindowView(accountID: accountID, controller: controller)
                .modelContainer(sharedModelContainer)
                .frame(minWidth: 460, minHeight: 360)
        } else {
            StorageRecoveryView(message: storageRecoveryMessage ?? "Codex Switcher couldn't open its local database.")
                .frame(minWidth: 460, minHeight: 360)
        }
    }
}

private struct AppBootstrap {
    let controller: AppController
    let modelContainer: ModelContainer?
    let storageRecoveryMessage: String?

    static func make() -> AppBootstrap {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "CodexSwitcher"
        let schema = Schema([StoredAccount.self])
        let autopilotEnabled = CodexSharedPreferences.autopilotEnabled

        if let uiTestScenario = UITestScenario.current {
            return makeUITestBootstrap(
                schema: schema,
                bundleIdentifier: bundleIdentifier,
                scenario: uiTestScenario
            )
        }

        if AppRuntimeEnvironment.isRunningUnitTests {
            return makeUnitTestBootstrap(
                schema: schema,
                bundleIdentifier: bundleIdentifier
            )
        }

        let authFileManager = SecurityScopedAuthFileManager()
        let secretStore = SharedKeychainSnapshotStore()
        let notificationManager = AccountSwitchNotificationManager()

        do {
            let modelContainer = try makeModelContainer(
                schema: schema,
                isStoredInMemoryOnly: false
            )
            let controller = AppController(
                authFileManager: authFileManager,
                secretStore: secretStore,
                notificationManager: notificationManager,
                modelContainer: modelContainer,
                autopilotEnabled: autopilotEnabled
            )
            return AppBootstrap(controller: controller, modelContainer: modelContainer, storageRecoveryMessage: nil)
        } catch {
            do {
                let fallbackContainer = try makeModelContainer(
                    schema: schema,
                    isStoredInMemoryOnly: true
                )
                let controller = AppController(
                    authFileManager: authFileManager,
                    secretStore: secretStore,
                    notificationManager: notificationManager,
                    startupAlert: UserFacingAlert(
                        title: "Using Temporary Storage",
                        message: "Codex Switcher couldn't open its local database and started with temporary in-memory storage instead. \(error.localizedDescription)"
                    ),
                    modelContainer: fallbackContainer,
                    autopilotEnabled: autopilotEnabled
                )
                return AppBootstrap(
                    controller: controller,
                    modelContainer: fallbackContainer,
                    storageRecoveryMessage: nil
                )
            } catch {
                let controller = AppController(
                    authFileManager: authFileManager,
                    secretStore: secretStore,
                    notificationManager: notificationManager,
                    startupAlert: UserFacingAlert(
                        title: "Storage Unavailable",
                        message: "Codex Switcher couldn't start its local database. \(error.localizedDescription)"
                    ),
                    autopilotEnabled: autopilotEnabled
                )
                return AppBootstrap(
                    controller: controller,
                    modelContainer: nil,
                    storageRecoveryMessage: error.localizedDescription
                )
            }
        }
    }

    private static func makeModelContainer(schema: Schema, isStoredInMemoryOnly: Bool) throws -> ModelContainer {
        // Preview and test containers stay local-only. The real app store
        // build uses CloudKit-backed SwiftData so saved accounts sync over
        // iCloud across the user's Macs.
        let configuration = ModelConfiguration(
            "Accounts",
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly,
            cloudKitDatabase: isStoredInMemoryOnly ? .none : .automatic
        )

        let modelContainer = try ModelContainer(for: schema, configurations: [configuration])

        if !isStoredInMemoryOnly {
            try StoredAccountLegacyCloudSyncRepair.normalizeLocalOnlyFieldsIfNeeded(
                in: modelContainer.mainContext
            )
        }

        return modelContainer
    }

    private static func makeUITestBootstrap(
        schema: Schema,
        bundleIdentifier: String,
        scenario: UITestScenario
    ) -> AppBootstrap {
        do {
            let modelContainer = try makeModelContainer(schema: schema, isStoredInMemoryOnly: true)
            let controller = AppController(
                authFileManager: UITestAuthFileManager(scenario: scenario),
                secretStore: UITestSecretStore(),
                notificationManager: UITestNotificationManager(),
                modelContainer: modelContainer,
                bundleIdentifier: bundleIdentifier
            )

            return AppBootstrap(
                controller: controller,
                modelContainer: modelContainer,
                storageRecoveryMessage: nil
            )
        } catch {
            let controller = AppController(
                authFileManager: UITestAuthFileManager(scenario: scenario),
                secretStore: UITestSecretStore(),
                notificationManager: UITestNotificationManager(),
                startupAlert: UserFacingAlert(
                    title: "UI Test Storage Unavailable",
                    message: error.localizedDescription
                ),
                bundleIdentifier: bundleIdentifier
            )

            return AppBootstrap(
                controller: controller,
                modelContainer: nil,
                storageRecoveryMessage: error.localizedDescription
            )
        }
    }

    private static func makeUnitTestBootstrap(
        schema: Schema,
        bundleIdentifier: String
    ) -> AppBootstrap {
        // Unit tests instantiate their own controllers and containers directly.
        // Keep the host app lightweight and local-only so the test runner
        // doesn't also boot CloudKit sync, file monitoring, and menu-bar
        // background behavior in parallel.
        do {
            let modelContainer = try makeModelContainer(schema: schema, isStoredInMemoryOnly: true)
            let controller = AppController(
                authFileManager: UITestAuthFileManager(scenario: .unlinked),
                secretStore: UITestSecretStore(),
                notificationManager: UITestNotificationManager(),
                modelContainer: modelContainer,
                bundleIdentifier: bundleIdentifier
            )

            return AppBootstrap(
                controller: controller,
                modelContainer: modelContainer,
                storageRecoveryMessage: nil
            )
        } catch {
            let controller = AppController(
                authFileManager: UITestAuthFileManager(scenario: .unlinked),
                secretStore: UITestSecretStore(),
                notificationManager: UITestNotificationManager(),
                startupAlert: UserFacingAlert(
                    title: "Unit Test Storage Unavailable",
                    message: error.localizedDescription
                ),
                bundleIdentifier: bundleIdentifier
            )

            return AppBootstrap(
                controller: controller,
                modelContainer: nil,
                storageRecoveryMessage: error.localizedDescription
            )
        }
    }
}

private struct StorageRecoveryView: View {
    let message: String

    var body: some View {
        ContentUnavailableView(
            "Storage Unavailable",
            systemImage: "externaldrive.badge.exclamationmark",
            description: Text(message)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

private struct MenuBarStorageRecoveryView: View {
    let message: String

    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Storage Unavailable", systemImage: "externaldrive.badge.exclamationmark")
                .font(.headline)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Button {
                NSApp.setActivationPolicy(.regular)
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .frame(width: 300, alignment: .leading)
        .padding(14)
    }
}

private struct SettingsView: View {
    @Bindable var controller: AppController
    @Environment(\.scenePhase) private var scenePhase
    @Binding var accountSwitchNotificationsEnabled: Bool
    @Binding var fiveHourResetNotificationsEnabled: Bool
    @Binding var sevenDayResetNotificationsEnabled: Bool
    @Binding var autopilotEnabled: Bool
    @Binding var showNoneAccount: Bool
    @Binding var automaticallyAddAccounts: Bool
    @Binding var automaticallyRemoveAccounts: Bool
    @Binding var showMenuBarExtra: Bool
    @Binding var menuBarIcon: MenuBarIconOption
    let areAppPreferencesAtDefaults: Bool
    let onResetSettings: () -> Void
    @State private var isUpdatingNotificationPreferences = false
    @State private var launchAtLoginState = CodexSharedLaunchAtLoginState.disabled
    @State private var presentedSettingsAlert: SettingsAlert?
    @State private var settingsChangeObservationTask: Task<Void, Never>?
    @State private var notificationAuthorizationStatus: UNAuthorizationStatus?

    var body: some View {
        Form {
            Section("Codex Folder") {
                LabeledContent("Path") {
                    Text(controller.linkedFolderPath ?? "Not selected")
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .foregroundStyle(controller.linkedFolderPath == nil ? .secondary : .primary)
                }

                Button(controller.settingsLinkButtonTitle, action: controller.beginLinkingCodexLocation)
            }

            Section {
                Toggle("Launch at Login", isOn: launchAtLoginBinding)
                Toggle("Show \"None\" Account", isOn: showNoneAccountBinding)
            } header: {
                Text("General")
            }

            Section {
                Toggle("Automatically Add Accounts", isOn: automaticAddAccountsBinding)
                Toggle("Automatically Remove Accounts", isOn: automaticRemoveAccountsBinding)
                Toggle("Automatically Switch Accounts", isOn: $autopilotEnabled)
            } header: {
                Text("Autopilot")
            } footer: {
                Text("Run in the background and automatically switch to the account with the most rate limit remaining.")
            }

            Section("Menu Bar") {
                Toggle("Show in Menu Bar", isOn: $showMenuBarExtra)

                Picker("Icon", selection: $menuBarIcon) {
                    ForEach(MenuBarIconOption.allCases) { option in
                        Label(option.title, systemImage: option.systemName)
                            .tag(option)
                    }
                }
                .disabled(!showMenuBarExtra)
            }

            Section {
                Toggle("Account Switch", isOn: accountSwitchNotificationsBinding)
                    .disabled(isUpdatingNotificationPreferences)

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
                    settingsActionLabel("Contact Us", systemImage: "envelope")
                }

                Link(destination: AppSupportLink.websiteURL) {
                    settingsActionLabel("Visit Our Website", systemImage: "globe")
                }

                Link(destination: AppSupportLink.termsOfServiceURL) {
                    settingsActionLabel("Terms of Service", systemImage: "doc.text")
                }

                Link(destination: AppSupportLink.privacyPolicyURL) {
                    settingsActionLabel("Privacy Policy", systemImage: "hand.raised")
                }

                Link(destination: AppSupportLink.sourceCodeURL) {
                    settingsActionLabel("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                }

                if let notificationSettingsURL = CodexNotificationSettingsLink.sectionFooterURL() {
                    Link(destination: notificationSettingsURL) {
                        settingsActionLabel("Notification Settings", systemImage: "bell.badge")
                    }
                }
            }

            Section("Danger Zone") {
                Button(role: .destructive) {
                    presentedSettingsAlert = .confirmation(.resetSettings)
                } label: {
                    settingsActionLabel(
                        "Reset Settings",
                        systemImage: "arrow.counterclockwise",
                        foregroundStyle: AnyShapeStyle(.red),
                        isEnabled: isResetSettingsEnabled
                    )
                }
                .buttonStyle(.plain)
                .disabled(!isResetSettingsEnabled)

                Button(role: .destructive) {
                    presentedSettingsAlert = .confirmation(.removeAllAccounts)
                } label: {
                    settingsActionLabel(
                        "Remove All Accounts",
                        systemImage: "trash",
                        foregroundStyle: AnyShapeStyle(.red),
                        isEnabled: controller.hasSavedAccounts
                    )
                }
                .buttonStyle(.plain)
                .disabled(!controller.hasSavedAccounts)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .task {
            launchAtLoginState = CodexSharedLaunchAtLoginService.currentState()
            startSettingsChangeObservationIfNeeded()
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
        .onDisappear {
            settingsChangeObservationTask?.cancel()
            settingsChangeObservationTask = nil
        }
        .alert(item: $presentedSettingsAlert) { alert in
            switch alert {
            case let .confirmation(action):
                Alert(
                    title: Text(action.title),
                    message: Text(action.message),
                    primaryButton: .destructive(Text(action.confirmationTitle)) {
                        switch action {
                        case .removeAllAccounts:
                            controller.removeAllAccounts()
                        case .resetSettings:
                            onResetSettings()
                            if launchAtLoginState.isEnabled {
                                updateLaunchAtLogin(isEnabled: false)
                            }
                        }
                    },
                    secondaryButton: .cancel()
                )
            case let .error(title, message):
                Alert(
                    title: Text(title),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private var isResetSettingsEnabled: Bool {
        !areAppPreferencesAtDefaults || launchAtLoginState.isEnabled
    }

    @ViewBuilder
    private var notificationSettingsFooter: some View {
        if let notificationAuthorizationStatus,
           CodexNotificationSettingsLink.shouldShowDisabledFooter(for: notificationAuthorizationStatus),
           let destination = CodexNotificationSettingsLink.sectionFooterURL() {
            Text(.init("Notifications are disabled in system settings. [Change](\(destination.absoluteString))"))
        }
    }

    private var accountSwitchNotificationsBinding: Binding<Bool> {
        Binding(
            get: {
                accountSwitchNotificationsEnabled
            },
            set: { newValue in
                updateNotificationPreference(.accountSwitch, isEnabled: newValue)
            }
        )
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

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: {
                launchAtLoginState.isEnabled
            },
            set: { newValue in
                updateLaunchAtLogin(isEnabled: newValue)
            }
        )
    }

    private var showNoneAccountBinding: Binding<Bool> {
        Binding(
            get: {
                showNoneAccount
            },
            set: { newValue in
                showNoneAccount = newValue
                CodexSharedPreferenceFeedback.postPreferencesDidChange()
            }
        )
    }

    private var automaticAddAccountsBinding: Binding<Bool> {
        Binding(
            get: {
                automaticallyAddAccounts
            },
            set: { newValue in
                automaticallyAddAccounts = newValue
                CodexSharedPreferenceFeedback.postPreferencesDidChange()
            }
        )
    }

    private var automaticRemoveAccountsBinding: Binding<Bool> {
        Binding(
            get: {
                automaticallyRemoveAccounts
            },
            set: { newValue in
                automaticallyRemoveAccounts = newValue
                CodexSharedPreferenceFeedback.postPreferencesDidChange()
            }
        )
    }

    private func settingsActionLabel(
        _ title: String,
        systemImage: String,
        foregroundStyle: AnyShapeStyle = AnyShapeStyle(.tint),
        isEnabled: Bool = true
    ) -> some View {
        Label(title, systemImage: systemImage)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(isEnabled ? foregroundStyle : AnyShapeStyle(.secondary))
            .contentShape(Rectangle())
    }

    private enum NotificationPreferenceKind {
        case accountSwitch
        case fiveHourReset
        case sevenDayReset
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
            let authorizationResult = await controller.requestNotificationAuthorizationForSettings()
            isUpdatingNotificationPreferences = false
            await refreshNotificationAuthorizationStatus()

            switch authorizationResult {
            case .enabled:
                setNotificationPreference(kind, isEnabled: true)
            case .denied:
                setNotificationPreference(kind, isEnabled: false)
                presentedSettingsAlert = .error(
                    title: "Notifications Disabled",
                    message: "Codex Switcher can only show notifications after you allow them in System Settings > Notifications."
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
        case .accountSwitch:
            accountSwitchNotificationsEnabled = isEnabled
            CodexSharedPreferenceFeedback.postPreferencesDidChange()
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

    private func updateLaunchAtLogin(isEnabled: Bool) {
        do {
            launchAtLoginState = try CodexSharedLaunchAtLoginService.setEnabled(isEnabled)
        } catch {
            launchAtLoginState = CodexSharedLaunchAtLoginService.currentState()
            presentedSettingsAlert = .error(
                title: "Couldn't Update Launch at Login",
                message: CodexSharedLaunchAtLoginService.userFacingMessage(for: error)
            )
        }
    }

    private func startSettingsChangeObservationIfNeeded() {
        guard settingsChangeObservationTask == nil else {
            return
        }

        settingsChangeObservationTask = Task { @MainActor in
            let notifications = DistributedNotificationCenter.default().notifications(
                named: CodexSharedPreferenceFeedback.didChangePreferencesNotification,
                object: nil
            )

            for await _ in notifications {
                launchAtLoginState = CodexSharedLaunchAtLoginService.currentState()
            }
        }
    }
}

private enum SettingsConfirmationAction: String, Identifiable {
    case removeAllAccounts
    case resetSettings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .removeAllAccounts:
            "Remove All Accounts"
        case .resetSettings:
            "Reset Settings"
        }
    }

    var message: String {
        switch self {
        case .removeAllAccounts:
            "This removes every saved account from Codex Switcher on this device and from iCloud sync."
        case .resetSettings:
            "This restores the menu bar and sorting preferences to their default values."
        }
    }

    var confirmationTitle: String {
        switch self {
        case .removeAllAccounts:
            "Remove All"
        case .resetSettings:
            "Reset"
        }
    }
}

private enum SettingsAlert: Identifiable {
    case confirmation(SettingsConfirmationAction)
    case error(title: String, message: String)

    var id: String {
        switch self {
        case let .confirmation(action):
            "confirmation-\(action.rawValue)"
        case let .error(title, message):
            "error-\(title)-\(message)"
        }
    }
}

private struct SortPreferencePersistenceView<Content: View>: View {
    @Bindable var controller: AppController
    @Binding var persistedSortCriterionRawValue: String
    @Binding var persistedSortDirectionRawValue: String
    let content: Content

    init(
        controller: AppController,
        persistedSortCriterionRawValue: Binding<String>,
        persistedSortDirectionRawValue: Binding<String>,
        @ViewBuilder content: () -> Content
    ) {
        self.controller = controller
        self._persistedSortCriterionRawValue = persistedSortCriterionRawValue
        self._persistedSortDirectionRawValue = persistedSortDirectionRawValue
        self.content = content()
    }

    var body: some View {
        content
            .task {
                controller.restoreSortPreferences(
                    sortCriterionRawValue: persistedSortCriterionRawValue,
                    sortDirectionRawValue: persistedSortDirectionRawValue
                )
            }
            .onChange(of: controller.sortCriterion) { _, newValue in
                persistedSortCriterionRawValue = newValue.rawValue
            }
            .onChange(of: controller.sortDirection) { _, newValue in
                persistedSortDirectionRawValue = newValue.rawValue
            }
    }
}

private enum AppPreferenceKey {
    static let showMenuBarExtra = "showMenuBarExtra"
    static let menuBarIconSystemName = "menuBarIconSystemName"
    static let sortCriterion = "sortCriterion"
    static let sortDirection = "sortDirection"
}

private enum AppPreferenceDefaults {
    static let showMenuBarExtra = true
    static let menuBarIconSystemName = MenuBarIconOption.defaultOption.systemName
    static let sortCriterionRawValue = AccountSortCriterion.dateAdded.rawValue
    static let sortDirectionRawValue = SortDirection.ascending.rawValue
}

private enum AppRuntimeEnvironment {
    static var isRunningUnitTests: Bool {
        // XCTest injects its framework into the host app for unit tests. Use
        // that host-only signal so normal launches keep the real CloudKit and
        // menu-bar behavior, while unit-test runs stay quiet and deterministic.
        NSClassFromString("XCTestCase") != nil
            && ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            && UITestScenario.current == nil
    }
}
