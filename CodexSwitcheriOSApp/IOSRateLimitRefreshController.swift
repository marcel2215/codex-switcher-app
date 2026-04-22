//
//  IOSRateLimitRefreshController.swift
//  Codex Switcher iOS App
//
//  Created by Codex on 2026-04-12.
//

import Observation
import OSLog
import SwiftData
import SwiftUI

@MainActor
@Observable
final class IOSRateLimitRefreshController {
    @ObservationIgnored private let engine: ForegroundRateLimitRefreshController

    init(
        provider: CodexRateLimitProviding = CodexRateLimitProvider(),
        credentialStore: SyncedRateLimitCredentialStoring = SyncedRateLimitCredentialStore(),
        logger: Logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "CodexSwitcher",
            category: "IOSRateLimitRefreshController"
        )
    ) {
        engine = ForegroundRateLimitRefreshController(
            policy: .iOS,
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

    func refreshDueAccountsForTesting() async {
        await engine.refreshDueAccountsForTesting()
    }

    func refreshNowForTesting(for identityKey: String) async {
        await engine.refreshNowForTesting(for: identityKey)
    }
}
