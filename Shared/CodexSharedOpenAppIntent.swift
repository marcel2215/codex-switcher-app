//
//  CodexSharedOpenAppIntent.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-13.
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
