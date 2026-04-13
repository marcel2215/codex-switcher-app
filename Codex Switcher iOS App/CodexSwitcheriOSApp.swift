//
//  CodexSwitcheriOSApp.swift
//  Codex Switcher iOS App
//
//  Created by Marcel Kwiatkowski on 2026-04-11.
//

import SwiftData
import SwiftUI

@main
struct CodexSwitcheriOSApp: App {
    @UIApplicationDelegateAdaptor(IOSApplicationDelegate.self) private var applicationDelegate
    private let bootstrap = IOSAppBootstrap.make()

    init() {
        CodexSharedPreferences.migrateLegacyPreferencesIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            switch bootstrap {
            case let .ready(modelContainer):
                AccountsRootView()
                    .modelContainer(modelContainer)
            case let .failed(message):
                StorageUnavailableView(message: message)
            }
        }
    }
}
