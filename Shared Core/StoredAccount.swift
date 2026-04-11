//
//  StoredAccount.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-07.
//

import Foundation
import SwiftData

@Model
final class StoredAccount {
    var id: UUID = UUID()
    @Attribute(.preserveValueOnDeletion)
    var identityKey: String = ""
    var name: String = ""
    var createdAt: Date = Date()
    var lastLoginAt: Date?
    var customOrder: Double = 0

    // Migration-only legacy field. New builds move auth snapshots into the
    // shared keychain and clear this value so SwiftData/CloudKit only carry
    // metadata, not the raw auth.json contents.
    var authFileContents: String?
    // CloudKit-synced minimal credential payload for live rate-limit fetches.
    // This intentionally stores only the small usage-API credential export,
    // never the full auth.json snapshot used on macOS for account switching.
    var syncedRateLimitCredentialJSON: String?
    var hasLocalSnapshot: Bool = false
    var authModeRaw: String = "chatgpt"
    var emailHint: String?
    var accountIdentifier: String?
    // These legacy-named fields store the remaining percentage for each Codex
    // limit window. The property names stay stable to avoid a disruptive
    // SwiftData + CloudKit schema rename, but the values themselves are the
    // user-facing "left" amount, not "used".
    var sevenDayLimitUsedPercent: Int?
    var fiveHourLimitUsedPercent: Int?
    var rateLimitsObservedAt: Date?
    var rateLimitDisplayVersion: Int?
    var iconSystemName: String = "key.fill"

    init(
        id: UUID = UUID(),
        identityKey: String,
        name: String,
        createdAt: Date = .now,
        lastLoginAt: Date? = nil,
        customOrder: Double,
        authFileContents: String? = nil,
        syncedRateLimitCredentialJSON: String? = nil,
        hasLocalSnapshot: Bool = false,
        authModeRaw: String,
        emailHint: String? = nil,
        accountIdentifier: String? = nil,
        sevenDayLimitUsedPercent: Int? = nil,
        fiveHourLimitUsedPercent: Int? = nil,
        rateLimitsObservedAt: Date? = nil,
        rateLimitDisplayVersion: Int? = 1,
        iconSystemName: String = "key.fill"
    ) {
        self.id = id
        self.identityKey = identityKey
        self.name = name
        self.createdAt = createdAt
        self.lastLoginAt = lastLoginAt
        self.customOrder = customOrder
        self.authFileContents = authFileContents
        self.syncedRateLimitCredentialJSON = syncedRateLimitCredentialJSON
        self.hasLocalSnapshot = hasLocalSnapshot
        self.authModeRaw = authModeRaw
        self.emailHint = emailHint
        self.accountIdentifier = accountIdentifier
        self.sevenDayLimitUsedPercent = sevenDayLimitUsedPercent
        self.fiveHourLimitUsedPercent = fiveHourLimitUsedPercent
        self.rateLimitsObservedAt = rateLimitsObservedAt
        self.rateLimitDisplayVersion = rateLimitDisplayVersion
        self.iconSystemName = iconSystemName
    }
}

extension StoredAccount {
    /// Returns the CloudKit-synced live-fetch credential when it decodes cleanly
    /// and still belongs to the expected identity. Callers must tolerate `nil`
    /// and fall back to another source instead of assuming this payload exists.
    func syncedRateLimitCredential(matching identityKey: String? = nil) -> SyncedRateLimitCredential? {
        guard let syncedRateLimitCredentialJSON, !syncedRateLimitCredentialJSON.isEmpty else {
            return nil
        }

        guard let credential = try? SyncedRateLimitCredential.decode(jsonString: syncedRateLimitCredentialJSON) else {
            return nil
        }

        guard let identityKey else {
            return credential
        }

        let normalizedIdentityKey = identityKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedIdentityKey.isEmpty, credential.identityKey == normalizedIdentityKey else {
            return nil
        }

        return credential
    }

    @discardableResult
    func updateSyncedRateLimitCredential(_ credential: SyncedRateLimitCredential?) -> Bool {
        let newValue: String?
        if let credential {
            newValue = try? credential.encodedJSONString()
        } else {
            newValue = nil
        }

        guard syncedRateLimitCredentialJSON != newValue else {
            return false
        }

        syncedRateLimitCredentialJSON = newValue
        return true
    }
}
