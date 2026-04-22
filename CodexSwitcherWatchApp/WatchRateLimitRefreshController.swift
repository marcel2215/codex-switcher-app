//
//  WatchRateLimitRefreshController.swift
//  Codex Switcher Watch App
//
//  Created by Codex on 2026-04-12.
//

import Observation
import OSLog
import SwiftData
import SwiftUI

@MainActor
@Observable
final class WatchRateLimitRefreshController {
    @ObservationIgnored private let engine: ForegroundRateLimitRefreshController

    init(
        provider: CodexRateLimitProviding = CodexRateLimitProvider(),
        credentialStore: SyncedRateLimitCredentialStoring = SyncedRateLimitCredentialStore(),
        logger: Logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "CodexSwitcher",
            category: "WatchRateLimitRefreshController"
        )
    ) {
        engine = ForegroundRateLimitRefreshController(
            policy: .watchOS,
            provider: provider,
            credentialStore: credentialStore,
            logger: logger
        )
    }

    func configure(modelContext: ModelContext) {
        engine.configure(modelContext: modelContext)
    }

    func setScenePhase(_ scenePhase: ScenePhase) {
        engine.setScenePhase(scenePhase)
    }

    func setVisible(_ isVisible: Bool, for identityKey: String) {
        engine.setVisible(isVisible, for: identityKey)
    }

    func setSelected(identityKey: String?) {
        engine.setSelected(identityKey: identityKey)
    }

    func reconcileKnownIdentityKeys(_ currentIdentityKeys: [String]) {
        engine.reconcileKnownIdentityKeys(currentIdentityKeys)
    }

    func refreshNow(for identityKey: String) {
        engine.refreshNow(for: identityKey)
    }

    func refreshTrackedAccountsNow() async {
        await engine.refreshTrackedAccountsNow()
    }

    func refreshNowAndWait(for identityKey: String) async {
        await engine.refreshNowAndWait(for: identityKey)
    }

    func hasSyncedCredential(for identityKey: String) async -> Bool {
        await engine.hasSyncedCredential(for: identityKey)
    }
}
