//
//  CodexSwitcherApp.swift
//  Codex Switcher
//
//  Created by Marcel Kwiatkowski on 2026-04-06.
//

import SwiftUI
import SwiftData

@main
struct CodexSwitcherApp: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var applicationDelegate
    @StateObject private var controller = AppController(
        authFileManager: SecurityScopedAuthFileManager(),
        notificationManager: AccountSwitchNotificationManager()
    )

    private let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            StoredAccount.self,
        ])

        // SwiftData will automatically back this store with CloudKit whenever the
        // matching iCloud capability is available in the app's signed entitlements.
        let configuration = ModelConfiguration(
            "Accounts",
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        Window("Codex Switcher", id: "main") {
            ContentView(controller: controller)
        }
        .defaultSize(width: 620, height: 720)
        .modelContainer(sharedModelContainer)
        .commands {
            AccountsCommands(controller: controller)
        }
    }
}
