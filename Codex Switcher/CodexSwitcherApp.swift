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
    @AppStorage(AppPreferenceKey.showMenuBarExtra) private var showMenuBarExtra = true
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
                    applicationDelegate.applyMenuBarPreference(isEnabled: showMenuBarExtra)
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
                showMenuBarExtra: showMenuBarExtraBinding
            )
            .frame(width: 520, height: 280)
            .task {
                applicationDelegate.applyMenuBarPreference(isEnabled: showMenuBarExtra)
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
            systemImage: "key.card.fill",
            isInserted: showMenuBarExtraBinding
        ) {
            if let sharedModelContainer {
                MenuBarAccountsView(controller: controller)
                    .modelContainer(sharedModelContainer)
                    .task {
                        applicationDelegate.applyMenuBarPreference(isEnabled: showMenuBarExtra)
                    }
            } else {
                MenuBarStorageRecoveryView(
                    message: storageRecoveryMessage ?? "Codex Switcher couldn't open its local database."
                )
                .task {
                    applicationDelegate.applyMenuBarPreference(isEnabled: showMenuBarExtra)
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
                applicationDelegate.applyMenuBarPreference(isEnabled: newValue)
            }
        )
    }

    @ViewBuilder
    private var rootContentView: some View {
        if let sharedModelContainer {
            ContentView(controller: controller)
                .modelContainer(sharedModelContainer)
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
                modelContainer: modelContainer
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
                    modelContainer: fallbackContainer
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
                    )
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
    @Binding var showMenuBarExtra: Bool
    @State private var isShowingLocationPicker = false

    var body: some View {
        Form {
            Section("Menu Bar") {
                Toggle("Show in Menu Bar", isOn: $showMenuBarExtra)

                Text("When enabled, pressing Command-Q hides Codex Switcher to the menu bar instead of fully quitting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        }
        .formStyle(.grouped)
        .padding(20)
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
}

private enum AppPreferenceKey {
    static let showMenuBarExtra = "showMenuBarExtra"
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
