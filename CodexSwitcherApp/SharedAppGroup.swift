//
//  SharedAppGroup.swift
//  Codex Switcher
//
//  Created by Marcel Kwiatkowski on 2026-04-08.
//

import Foundation

enum CodexSharedAppGroup {
    nonisolated static let identifier = "group.com.marcel2215.codexswitcher"
    nonisolated static let stateFilename = "SharedCodexState.json"
    nonisolated static let snapshotAvailabilityFilename = "LocalSnapshotAvailability.json"
    nonisolated static let bookmarkFilename = "LinkedCodexFolderShared.bookmark"
    nonisolated static let legacyBookmarkFilename = "LinkedCodexFolder.bookmark"
    nonisolated static let appCommandFilename = "PendingCodexAppCommands.json"
    nonisolated static let appCommandResultFilename = "PendingCodexAppCommandResults.json"
    nonisolated static let pendingAccountOpenFilename = "PendingCodexAccountOpenRequest.json"
    nonisolated static let lockFilename = "CodexAccountSwitch.lock"

    nonisolated static func containerURL(fileManager: FileManager = .default) throws -> URL {
        guard let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
            throw CodexSharedDataStoreError.containerUnavailable(identifier)
        }

        return containerURL
    }
}

enum CodexSharedDataStoreError: LocalizedError {
    case containerUnavailable(String)

    nonisolated var errorDescription: String? {
        switch self {
        case let .containerUnavailable(identifier):
            "Codex Switcher couldn't open its shared App Group container (\(identifier))."
        }
    }
}
