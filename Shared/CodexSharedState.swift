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
    var hasLocalSnapshot: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case iconSystemName
        case emailHint
        case accountIdentifier
        case authModeRaw
        case lastLoginAt
        case sevenDayLimitUsedPercent
        case fiveHourLimitUsedPercent
        case rateLimitsObservedAt
        case sortOrder
        case hasLocalSnapshot
        case authFileContents
    }

    init(
        id: String,
        name: String,
        iconSystemName: String,
        emailHint: String?,
        accountIdentifier: String?,
        authModeRaw: String,
        lastLoginAt: Date?,
        sevenDayLimitUsedPercent: Int?,
        fiveHourLimitUsedPercent: Int?,
        rateLimitsObservedAt: Date?,
        sortOrder: Double,
        hasLocalSnapshot: Bool
    ) {
        self.id = id
        self.name = name
        self.iconSystemName = iconSystemName
        self.emailHint = emailHint
        self.accountIdentifier = accountIdentifier
        self.authModeRaw = authModeRaw
        self.lastLoginAt = lastLoginAt
        self.sevenDayLimitUsedPercent = sevenDayLimitUsedPercent
        self.fiveHourLimitUsedPercent = fiveHourLimitUsedPercent
        self.rateLimitsObservedAt = rateLimitsObservedAt
        self.sortOrder = sortOrder
        self.hasLocalSnapshot = hasLocalSnapshot
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        iconSystemName = try container.decode(String.self, forKey: .iconSystemName)
        emailHint = try container.decodeIfPresent(String.self, forKey: .emailHint)
        accountIdentifier = try container.decodeIfPresent(String.self, forKey: .accountIdentifier)
        authModeRaw = try container.decode(String.self, forKey: .authModeRaw)
        lastLoginAt = try container.decodeIfPresent(Date.self, forKey: .lastLoginAt)
        sevenDayLimitUsedPercent = try container.decodeIfPresent(Int.self, forKey: .sevenDayLimitUsedPercent)
        fiveHourLimitUsedPercent = try container.decodeIfPresent(Int.self, forKey: .fiveHourLimitUsedPercent)
        rateLimitsObservedAt = try container.decodeIfPresent(Date.self, forKey: .rateLimitsObservedAt)
        sortOrder = try container.decode(Double.self, forKey: .sortOrder)
        hasLocalSnapshot = try container.decodeIfPresent(Bool.self, forKey: .hasLocalSnapshot)
            ?? (try container.decodeIfPresent(String.self, forKey: .authFileContents)?.isEmpty == false)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(iconSystemName, forKey: .iconSystemName)
        try container.encodeIfPresent(emailHint, forKey: .emailHint)
        try container.encodeIfPresent(accountIdentifier, forKey: .accountIdentifier)
        try container.encode(authModeRaw, forKey: .authModeRaw)
        try container.encodeIfPresent(lastLoginAt, forKey: .lastLoginAt)
        try container.encodeIfPresent(sevenDayLimitUsedPercent, forKey: .sevenDayLimitUsedPercent)
        try container.encodeIfPresent(fiveHourLimitUsedPercent, forKey: .fiveHourLimitUsedPercent)
        try container.encodeIfPresent(rateLimitsObservedAt, forKey: .rateLimitsObservedAt)
        try container.encode(sortOrder, forKey: .sortOrder)
        try container.encode(hasLocalSnapshot, forKey: .hasLocalSnapshot)
    }
}

nonisolated struct SharedCodexState: Codable, Sendable {
    nonisolated static let currentSchemaVersion = 4

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
