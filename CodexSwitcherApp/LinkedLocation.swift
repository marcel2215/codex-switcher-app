//
//  LinkedLocation.swift
//  Codex Switcher
//
//  Created by Marcel Kwiatkowski on 2026-04-11.
//

import Foundation

nonisolated struct AuthFileReadResult: Sendable, Equatable {
    nonisolated let url: URL
    nonisolated let contents: String
}

nonisolated struct AuthLinkedLocation: Sendable, Equatable {
    nonisolated let folderURL: URL
    nonisolated let credentialStoreHint: CodexCredentialStoreHint

    nonisolated var authFileURL: URL {
        folderURL.appending(path: "auth.json", directoryHint: .notDirectory)
    }

    nonisolated var configFileURL: URL {
        folderURL.appending(path: "config.toml", directoryHint: .notDirectory)
    }
}

nonisolated enum CodexCredentialStoreHint: String, Sendable, Equatable {
    case unknown
    case file
    case keyring
    case auto

    nonisolated var isSupportedForFileSwitching: Bool {
        switch self {
        case .unknown, .file:
            true
        case .keyring, .auto:
            false
        }
    }

    nonisolated var displayName: String {
        switch self {
        case .unknown:
            "unknown"
        case .file:
            "file"
        case .keyring:
            "keyring"
        case .auto:
            "auto"
        }
    }
}
