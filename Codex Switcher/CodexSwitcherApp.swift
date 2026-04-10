//
//  CodexSwitcherApp.swift
//  Codex Switcher
//
//  Created by Marcel Kwiatkowski on 2026-04-06.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

@main
struct CodexSwitcherApp: App {
    @AppStorage(
        CodexSharedPreferenceKey.notificationsEnabled,
        store: CodexSharedPreferences.userDefaults
    ) private var showNotifications = CodexSharedPreferenceDefaults.notificationsEnabled
    @AppStorage(
        CodexSharedPreferenceKey.autopilotEnabled,
        store: CodexSharedPreferences.userDefaults
    ) private var autopilotEnabled = CodexSharedPreferenceDefaults.autopilotEnabled
    @AppStorage(AppPreferenceKey.showMenuBarExtra) private var showMenuBarExtra = AppPreferenceDefaults.showMenuBarExtra
    @AppStorage(AppPreferenceKey.menuBarIconSystemName) private var persistedMenuBarIconSystemName = AppPreferenceDefaults.menuBarIconSystemName
    @AppStorage(AppPreferenceKey.sortCriterion) private var persistedSortCriterionRawValue = AppPreferenceDefaults.sortCriterionRawValue
    @AppStorage(AppPreferenceKey.sortDirection) private var persistedSortDirectionRawValue = AppPreferenceDefaults.sortDirectionRawValue
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var applicationDelegate
    @State private var controller: AppController

    private let sharedModelContainer: ModelContainer?
    private let storageRecoveryMessage: String?

    init() {
        let bootstrap = AppBootstrap.make()
        self.sharedModelContainer = bootstrap.modelContainer
        self.storageRecoveryMessage = bootstrap.storageRecoveryMessage
        _controller = State(initialValue: bootstrap.controller)
    }

    var body: some Scene {
        mainWindowScene
        settingsScene
        menuBarScene
    }

    @SceneBuilder
    private var mainWindowScene: some Scene {
        Window("Codex Switcher", id: "main") {
            rootContentView
                .task {
                    applyRuntimePreferences()
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
    private var settingsScene: some Scene {
        Settings {
            SettingsView(
                controller: controller,
                showNotifications: $showNotifications,
                autopilotEnabled: autopilotBinding,
                showMenuBarExtra: showMenuBarExtraBinding,
                menuBarIcon: menuBarIconBinding,
                areAppPreferencesAtDefaults: areAppPreferencesAtDefaults,
                onResetSettings: resetStoredSettingsToDefaults
            )
            .frame(width: 520, height: 590)
            .task {
                applyRuntimePreferences()
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
                        applyRuntimePreferences()
                    }
            } else {
                MenuBarStorageRecoveryView(
                    message: storageRecoveryMessage ?? "Codex Switcher couldn't open its local database."
                )
                .task {
                    applyRuntimePreferences()
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
        showNotifications = CodexSharedPreferenceDefaults.notificationsEnabled
        autopilotBinding.wrappedValue = CodexSharedPreferenceDefaults.autopilotEnabled
        showMenuBarExtraBinding.wrappedValue = AppPreferenceDefaults.showMenuBarExtra
        menuBarIconBinding.wrappedValue = MenuBarIconOption.defaultOption
        persistedSortCriterionRawValue = AppPreferenceDefaults.sortCriterionRawValue
        persistedSortDirectionRawValue = AppPreferenceDefaults.sortDirectionRawValue
        controller.restoreSortPreferences(
            sortCriterionRawValue: persistedSortCriterionRawValue,
            sortDirectionRawValue: persistedSortDirectionRawValue
        )
    }

    private var areAppPreferencesAtDefaults: Bool {
        showNotifications == CodexSharedPreferenceDefaults.notificationsEnabled
            && autopilotEnabled == CodexSharedPreferenceDefaults.autopilotEnabled
            && showMenuBarExtra == AppPreferenceDefaults.showMenuBarExtra
            && persistedMenuBarIconSystemName == AppPreferenceDefaults.menuBarIconSystemName
            && persistedSortCriterionRawValue == AppPreferenceDefaults.sortCriterionRawValue
            && persistedSortDirectionRawValue == AppPreferenceDefaults.sortDirectionRawValue
    }

    private func applyRuntimePreferences() {
        controller.setAutopilotEnabled(autopilotEnabled)
        applicationDelegate.applyBackgroundResidency(
            menuBarEnabled: showMenuBarExtra,
            autopilotEnabled: autopilotEnabled
        )
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
        let secretStore = KeychainAccountSecretStore(bundleIdentifier: bundleIdentifier)
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

        return try ModelContainer(for: schema, configurations: [configuration])
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
    @Binding var showNotifications: Bool
    @Binding var autopilotEnabled: Bool
    @Binding var showMenuBarExtra: Bool
    @Binding var menuBarIcon: MenuBarIconOption
    let areAppPreferencesAtDefaults: Bool
    let onResetSettings: () -> Void
    @State private var isShowingLocationPicker = false
    @State private var isUpdatingNotificationsPreference = false
    @State private var launchAtLoginState = LaunchAtLoginState.disabled
    @State private var presentedSettingsAlert: SettingsAlert?

    var body: some View {
        Form {
            Section("General") {
                Toggle("Show Notifications", isOn: notificationsBinding)
                    .disabled(isUpdatingNotificationsPreference)

                Toggle("Launch at Login", isOn: launchAtLoginBinding)

                if launchAtLoginState.requiresApproval {
                    Text("Requires approval in System Settings > General > Login Items.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Autopilot") {
                Toggle("Automatically Switch Account", isOn: $autopilotEnabled)

                Text("Run in the background and automatically switch to the account with the most rate limit reamining.")
                .font(.caption)
                .foregroundStyle(.secondary)
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

            Section("Codex Folder") {
                LabeledContent("Path") {
                    Text(controller.linkedFolderPath ?? "Not selected")
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .foregroundStyle(controller.linkedFolderPath == nil ? .secondary : .primary)
                }

                Button(controller.settingsLinkButtonTitle) {
                    isShowingLocationPicker = true
                }
            }

            Section("About") {
                LabeledContent("Version") {
                    Text(AppAboutInfo.current.version)
                }

                LabeledContent("Build") {
                    Text(AppAboutInfo.current.build)
                }
            }

            Section("Actions") {
                Link(destination: AppSupportLink.contactURL) {
                    settingsActionLabel("Contact Us", systemImage: "envelope")
                }

                Link(destination: AppSupportLink.privacyPolicyURL) {
                    settingsActionLabel("Privacy Policy", systemImage: "hand.raised")
                }

                Link(destination: AppSupportLink.sourceCodeURL) {
                    settingsActionLabel("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
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
            launchAtLoginState = LaunchAtLoginService.currentState()
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
        .fileImporter(
            isPresented: $isShowingLocationPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false,
            onCompletion: controller.handleLocationImport
        )
        .fileDialogCustomizationID("codex-auth-location")
        .fileDialogDefaultDirectory(FileManager.default.homeDirectoryForCurrentUser)
        .fileDialogBrowserOptions([.includeHiddenFiles])
    }

    private var isResetSettingsEnabled: Bool {
        !areAppPreferencesAtDefaults || launchAtLoginState.isEnabled
    }

    private var notificationsBinding: Binding<Bool> {
        Binding(
            get: {
                showNotifications
            },
            set: { newValue in
                updateNotificationsPreference(isEnabled: newValue)
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

    private func updateNotificationsPreference(isEnabled: Bool) {
        guard !isUpdatingNotificationsPreference else {
            return
        }

        guard isEnabled else {
            showNotifications = false
            return
        }

        showNotifications = true
        isUpdatingNotificationsPreference = true

        Task { @MainActor in
            let authorizationResult = await controller.requestNotificationAuthorizationForSettings()
            isUpdatingNotificationsPreference = false

            switch authorizationResult {
            case .enabled:
                showNotifications = true
            case .denied:
                showNotifications = false
                presentedSettingsAlert = .error(
                    title: "Notifications Disabled",
                    message: "Codex Switcher can only show account-switch notifications after you allow notifications in macOS. You can enable them later in System Settings > Notifications."
                )
            case let .failed(message):
                showNotifications = false
                presentedSettingsAlert = .error(
                    title: "Couldn't Enable Notifications",
                    message: message
                )
            }
        }
    }

    private func updateLaunchAtLogin(isEnabled: Bool) {
        do {
            launchAtLoginState = try LaunchAtLoginService.setEnabled(isEnabled)
        } catch {
            launchAtLoginState = LaunchAtLoginService.currentState()
            presentedSettingsAlert = .error(
                title: "Couldn't Update Launch at Login",
                message: LaunchAtLoginService.userFacingMessage(for: error)
            )
        }
    }
}

private struct AppAboutInfo {
    let version: String
    let build: String

    static var current: AppAboutInfo {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        return AppAboutInfo(version: version, build: build)
    }
}

private enum AppSupportLink {
    static let contactURL = URL(
        string: "mailto:marcel2215@icloud.com?subject=Codex%20Switcher%20Support"
    )!
    static let sourceCodeURL = URL(string: "https://github.com/marcel2215/codex-switcher")!
    static let privacyPolicyURL = URL(string: "https://example.com/privacy")!
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
