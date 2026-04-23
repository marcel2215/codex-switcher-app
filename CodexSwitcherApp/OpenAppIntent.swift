//
//  OpenAppIntent.swift
//  Codex Switcher
//
//  Created by Marcel Kwiatkowski on 2026-04-13.
//

@preconcurrency import AppIntents

struct OpenCodexSwitcherIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Codex Switcher"
    static let description = IntentDescription("Opens Codex Switcher.")
    static let supportedModes: IntentModes = .foreground

    func perform() async throws -> some IntentResult {
        .result()
    }
}

#if CODEX_ACCOUNT_SPOTLIGHT
struct OpenCodexAccountIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Codex Account"
    static let description = IntentDescription("Opens Codex Switcher to one of your saved accounts.")
    static let openAppWhenRun = true

    @Parameter(title: "Account")
    var target: CodexAccountEntity

    init() {}

    init(target: CodexAccountEntity) {
        self.target = target
    }

    func perform() async throws -> some IntentResult {
        try CodexPendingAccountOpenRequestStore().save(identityKey: target.id)
        CodexPendingAccountOpenSignal.postRequestQueuedSignal()
        return .result()
    }
}
#endif
