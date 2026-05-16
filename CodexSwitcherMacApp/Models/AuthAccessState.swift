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
            L10n.string("Link Codex Folder", comment: "Authentication status title.")
        case .ready:
            L10n.string("Codex Linked", comment: "Authentication status title.")
        case .missingAuthFile:
            L10n.string("No auth.json", comment: "Authentication status title.")
        case .locationUnavailable:
            L10n.string("Codex Folder Missing", comment: "Authentication status title.")
        case .accessDenied:
            L10n.string("Permission Needed", comment: "Authentication status title.")
        case .corruptAuthFile:
            L10n.string("Invalid auth.json", comment: "Authentication status title.")
        case .unsupportedCredentialStore:
            L10n.string("Unsupported Credential Store", comment: "Authentication status title.")
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
                "Choose the Codex folder that contains auth.json.",
                comment: "Authentication status message shown before a Codex folder is linked."
            )
        case let .ready(linkedFolder):
            return L10n.format(
                "Linked to %@.",
                linkedFolder.path,
                comment: "Authentication status message. The argument is the linked folder path."
            )
        case let .missingAuthFile(linkedFolder, credentialStoreHint):
            if credentialStoreHint == .file {
                return L10n.format(
                    "No auth.json was found in %@. Codex may be logged out.",
                    linkedFolder.path,
                    comment: "Authentication status message. The argument is the linked folder path."
                )
            }

            return L10n.format(
                "No auth.json was found in %@. Codex may be logged out, may be using a different CODEX_HOME, or may be using keyring or auto credential storage.",
                linkedFolder.path,
                comment: "Authentication status message. The argument is the linked folder path."
            )
        case let .locationUnavailable(linkedFolder):
            return L10n.format(
                "The linked Codex folder is no longer available: %@.",
                linkedFolder.path,
                comment: "Authentication status message. The argument is the linked folder path."
            )
        case let .accessDenied(linkedFolder):
            return L10n.format(
                "Codex Switcher no longer has permission to access %@. Relink the folder to continue.",
                linkedFolder.path,
                comment: "Authentication status message. The argument is the linked folder path."
            )
        case let .corruptAuthFile(linkedFolder):
            return L10n.format(
                "auth.json in %@ isn't valid JSON or doesn't contain a supported Codex account payload.",
                linkedFolder.path,
                comment: "Authentication status message. The argument is the linked folder path."
            )
        case let .unsupportedCredentialStore(linkedFolder, mode):
            return L10n.format(
                "The linked Codex folder at %1$@ is configured for %2$@ credential storage. Codex Switcher only supports file-backed auth.json switching.",
                linkedFolder.path,
                mode.displayName,
                comment: "Authentication status message. Arguments are folder path and credential store mode."
            )
        }
    }
}
