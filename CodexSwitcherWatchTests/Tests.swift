//
//  Tests.swift
//  Codex Switcher Watch Tests
//
//  Created by Codex on 2026-04-12.
//

import SwiftData
import Testing
@testable import Codex_Switcher_Watch_App

struct Tests {
    @Test
    @MainActor
    func bootstrapCreatesInMemoryContainer() throws {
        let bootstrap = WatchAppBootstrap.make(isStoredInMemoryOnly: true)

        switch bootstrap {
        case let .ready(modelContainer):
            let descriptor = FetchDescriptor<StoredAccount>()
            let accounts = try modelContainer.mainContext.fetch(descriptor)
            #expect(accounts.isEmpty)
        case let .failed(message):
            Issue.record("Expected in-memory bootstrap to succeed, got: \(message)")
        }
    }
}
