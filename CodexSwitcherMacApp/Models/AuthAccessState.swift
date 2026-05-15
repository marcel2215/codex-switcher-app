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
            L10n.string("authAccess.title.unlinked", defaultValue: "Link Codex Folder")
        case .ready:
            L10n.string("authAccess.title.ready", defaultValue: "Codex Linked")
        case .missingAuthFile:
            L10n.string("authAccess.title.missingAuthFile", defaultValue: "No auth.json")
        case .locationUnavailable:
            L10n.string("authAccess.title.locationUnavailable", defaultValue: "Codex Folder Missing")
        case .accessDenied:
            L10n.string("authAccess.title.accessDenied", defaultValue: "Permission Needed")
        case .corruptAuthFile:
            L10n.string("authAccess.title.corruptAuthFile", defaultValue: "Invalid auth.json")
        case .unsupportedCredentialStore:
            L10n.string("authAccess.title.unsupportedCredentialStore", defaultValue: "Unsupported Credential Store")
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
            return L10n.string(
                "authAccess.message.unlinked",
                defaultValue: "Choose the Codex folder that contains auth.json."
            )
        case let .ready(linkedFolder):
            return L10n.string(
                "authAccess.message.ready",
                defaultValue: "Linked to %@.",
                linkedFolder.path
            )
        case let .missingAuthFile(linkedFolder, credentialStoreHint):
            if credentialStoreHint == .file {
                return L10n.string(
                    "authAccess.message.missingAuthFile.file",
                    defaultValue: "No auth.json was found in %@. Codex may be logged out.",
                    linkedFolder.path
                )
            }

            return L10n.string(
                "authAccess.message.missingAuthFile.otherStore",
                defaultValue: "No auth.json was found in %@. Codex may be logged out, may be using a different CODEX_HOME, or may be using keyring or auto credential storage.",
                linkedFolder.path
            )
        case let .locationUnavailable(linkedFolder):
            return L10n.string(
                "authAccess.message.locationUnavailable",
                defaultValue: "The linked Codex folder is no longer available: %@.",
                linkedFolder.path
            )
        case let .accessDenied(linkedFolder):
            return L10n.string(
                "authAccess.message.accessDenied",
                defaultValue: "Codex Switcher no longer has permission to access %@. Relink the folder to continue.",
                linkedFolder.path
            )
        case let .corruptAuthFile(linkedFolder):
            return L10n.string(
                "authAccess.message.corruptAuthFile",
                defaultValue: "auth.json in %@ isn't valid JSON or doesn't contain a supported Codex account payload.",
                linkedFolder.path
            )
        case let .unsupportedCredentialStore(linkedFolder, mode):
            return L10n.string(
                "authAccess.message.unsupportedCredentialStore",
                defaultValue: "The linked Codex folder at %@ is configured for %@ credential storage. Codex Switcher only supports file-backed auth.json switching.",
                linkedFolder.path,
                mode.displayName
            )
        }
    }
}
