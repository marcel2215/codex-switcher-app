//
//  CodexSpotlightIndexer.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-16.
//

import AppIntents
import Foundation

#if canImport(CoreSpotlight)
import CoreSpotlight
#endif

enum CodexSpotlightIndexer {
    /// Rebuild the account index from the latest shared state so Spotlight
    /// search follows CloudKit/iCloud-driven account changes on every device.
    static func refresh(with sharedState: SharedCodexState) async throws {
#if CODEX_ACCOUNT_SPOTLIGHT && canImport(CoreSpotlight)
        let searchableIndex = CSSearchableIndex.default()
        try await searchableIndex.deleteAppEntities(ofType: CodexAccountEntity.self)

        let entities = CodexSharedAccountIntentResolver.allEntities(in: sharedState)
        guard !entities.isEmpty else {
            return
        }

        try await searchableIndex.indexAppEntities(entities)
#endif
    }
}
