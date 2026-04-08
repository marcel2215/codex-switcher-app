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
        Window("Codex Switcher", id: "main") {
            Group {
                if let sharedModelContainer {
                    ContentView(controller: controller)
                        .modelContainer(sharedModelContainer)
                } else {
                    StorageRecoveryView(message: storageRecoveryMessage ?? "Codex Switcher couldn't open its local database.")
                }
            }
        }
        .defaultSize(width: 620, height: 720)
        .commands {
            AccountsCommands(controller: controller)
        }

        Settings {
            SettingsView(controller: controller)
                .frame(width: 520, height: 220)
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
                notificationManager: notificationManager
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
                    )
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

private struct SettingsView: View {
    @Bindable var controller: AppController
    @State private var isShowingLocationPicker = false

    var body: some View {
        Form {
            Section("Codex Folder") {
                Text(controller.linkedFolderPath ?? "Not selected")
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .foregroundStyle(controller.linkedFolderPath == nil ? .secondary : .primary)

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
