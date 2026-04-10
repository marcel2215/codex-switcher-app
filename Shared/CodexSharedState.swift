//
//  CodexSharedState.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-08.
//

import Foundation

nonisolated enum SharedCodexAuthState: String, Codable, Sendable, Equatable {
    case unlinked
    case ready
    case loggedOut
    case locationUnavailable
    case accessDenied
    case corruptAuthFile
    case unsupportedCredentialStore

    nonisolated var canAttemptSwitch: Bool {
        switch self {
        case .ready, .loggedOut:
            true
        case .unlinked, .locationUnavailable, .accessDenied, .corruptAuthFile, .unsupportedCredentialStore:
            false
        }
    }
}

nonisolated struct SharedCodexAccountRecord: Codable, Hashable, Identifiable, Sendable {
    /// Widgets, controls, and intents use the stable semantic account identity
    /// instead of the local SwiftData UUID so configurations survive sync and
    /// duplicate reconciliation.
    let id: String
    var name: String
    var iconSystemName: String
    var emailHint: String?
    var accountIdentifier: String?
    var authModeRaw: String
    var lastLoginAt: Date?
    var sevenDayLimitUsedPercent: Int?
    var fiveHourLimitUsedPercent: Int?
    var rateLimitsObservedAt: Date?
    var sortOrder: Double
    var authFileContents: String?
}

nonisolated struct SharedCodexState: Codable, Sendable {
    nonisolated static let currentSchemaVersion = 3

    var schemaVersion: Int
    var authState: SharedCodexAuthState
    var linkedFolderPath: String?
    var currentAccountID: String?
    var selectedAccountID: String?
    /// Only treat `selectedAccountID` as meaningful when the main account list
    /// is currently on-screen. Older snapshots omit this field, which safely
    /// decodes as nil and therefore disables stale "selected account" results.
    var selectedAccountIsLive: Bool?
    var accounts: [SharedCodexAccountRecord]
    var updatedAt: Date

    nonisolated static let empty = SharedCodexState(
        schemaVersion: currentSchemaVersion,
        authState: .unlinked,
        linkedFolderPath: nil,
        currentAccountID: nil,
        selectedAccountID: nil,
        selectedAccountIsLive: false,
        accounts: [],
        updatedAt: .distantPast
    )

    nonisolated func account(withIdentityKey identityKey: String) -> SharedCodexAccountRecord? {
        accounts.first(where: { $0.id == identityKey })
    }

    nonisolated var currentAccount: SharedCodexAccountRecord? {
        guard let currentAccountID else {
            return nil
        }

        return account(withIdentityKey: currentAccountID)
    }

    nonisolated var selectedAccount: SharedCodexAccountRecord? {
        guard (selectedAccountIsLive ?? false), let selectedAccountID else {
            return nil
        }

        return account(withIdentityKey: selectedAccountID)
    }
}
