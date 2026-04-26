//
//  App.swift
//  Codex Switcher Watch App
//
//  Created by Marcel Kwiatkowski on 2026-04-11.
//

import SwiftData
import SwiftUI

@main
struct CodexSwitcherWatchApp: App {
    @State private var bootstrap = WatchAppBootstrap.make()

    init() {
        CodexSharedPreferences.migrateLegacyPreferencesIfNeeded()
        CodexSharedContainerPreflight.logFailureIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            switch bootstrap {
            case let .ready(modelContainer):
                WatchAccountsRootView()
                    .modelContainer(modelContainer)
            case let .failed(message):
                WatchStorageUnavailableView(
                    message: message,
                    onRetry: {
                        bootstrap = WatchAppBootstrap.make()
                    }
                )
            }
        }
    }
}
