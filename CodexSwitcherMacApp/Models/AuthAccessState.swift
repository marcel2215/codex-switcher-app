//
//  AuthAccessState.swift
//  Codex Switcher Mac App
//
//  Created by Marcel Kwiatkowski on 2026-04-08.
//

import Foundation

enum AuthAccessState: Equatable {
    case unlinked
    case ready(linkedFolder: URL)
    case missingAuthFile(linkedFolder: URL, credentialStoreHint: CodexCredentialStoreHint)
    case locationUnavailable(linkedFolder: URL)
    case accessDenied(linkedFolder: URL)
    case corruptAuthFile(linkedFolder: URL)
    case unsupportedCredentialStore(linkedFolder: URL, mode: CodexCredentialStoreHint)

    var showsInlineStatus: Bool {
        switch self {
        case .ready, .missingAuthFile:
            false
        case .unlinked,
             .locationUnavailable,
             .accessDenied,
             .corruptAuthFile,
             .unsupportedCredentialStore:
            true
        }
    }

    var linkedFolderURL: URL? {
        switch self {
        case .unlinked:
            nil
        case let .ready(linkedFolder),
             let .missingAuthFile(linkedFolder, _),
             let .locationUnavailable(linkedFolder),
             let .accessDenied(linkedFolder),
             let .corruptAuthFile(linkedFolder),
             let .unsupportedCredentialStore(linkedFolder, _):
            linkedFolder
        }
    }

    var title: String {
        switch self {
        case .unlinked:
            "Link Codex Folder"
        case .ready:
            "Codex Linked"
        case .missingAuthFile:
            "No auth.json"
        case .locationUnavailable:
            "Codex Folder Missing"
        case .accessDenied:
            "Permission Needed"
        case .corruptAuthFile:
            "Invalid auth.json"
        case .unsupportedCredentialStore:
            "Unsupported Credential Store"
        }
    }

    var systemImage: String {
        switch self {
        case .unlinked:
            "folder.badge.questionmark"
        case .ready:
            "checkmark.circle"
        case .missingAuthFile:
            "doc.questionmark"
        case .locationUnavailable:
            "folder.badge.minus"
        case .accessDenied:
            "lock.slash"
        case .corruptAuthFile:
            "exclamationmark.triangle"
        case .unsupportedCredentialStore:
            "key.slash"
        }
    }

    var message: String {
        switch self {
        case .unlinked:
            return "Choose the Codex folder that contains auth.json."
        case let .ready(linkedFolder):
            return "Linked to \(linkedFolder.path)."
        case let .missingAuthFile(linkedFolder, credentialStoreHint):
            if credentialStoreHint == .file {
                return "No auth.json was found in \(linkedFolder.path). Codex may be logged out."
            }

            return "No auth.json was found in \(linkedFolder.path). Codex may be logged out, may be using a different CODEX_HOME, or may be using keyring or auto credential storage."
        case let .locationUnavailable(linkedFolder):
            return "The linked Codex folder is no longer available: \(linkedFolder.path)."
        case let .accessDenied(linkedFolder):
            return "Codex Switcher no longer has permission to access \(linkedFolder.path). Relink the folder to continue."
        case let .corruptAuthFile(linkedFolder):
            return "auth.json in \(linkedFolder.path) isn't valid JSON or doesn't contain a supported Codex account payload."
        case let .unsupportedCredentialStore(linkedFolder, mode):
            return "The linked Codex folder at \(linkedFolder.path) is configured for \(mode.displayName) credential storage. Codex Switcher only supports file-backed auth.json switching."
        }
    }
}
