//
//  StoredAccount.swift
//  Codex Switcher
//
//  Created by Marcel Kwiatkowski on 2026-04-07.
//

import Foundation
import SwiftData

enum StoredAccountAvailability: String, Codable, Sendable {
    case available
    case unavailableUnauthorized
}

enum StoredAccountUnavailableReason: String, Codable, Sendable {
    case unauthorized
    case refreshTokenExpired
    case refreshTokenRevoked
    case refreshTokenReused
    case accountMismatch
    case missingCredentials
    case corruptedSnapshot
}

@Model
final class StoredAccount {
    var id: UUID = UUID()
    @Attribute(.preserveValueOnDeletion)
    var identityKey: String = ""
    var name: String = ""
    @Attribute(.allowsCloudEncryption)
    var notes: String = ""
    var createdAt: Date = Date()
    var lastLoginAt: Date?
    var customOrder: Double = 0
    var isPinned: Bool = false

    // Migration-only legacy field. New builds move auth snapshots into the
    // shared keychain and clear this value so SwiftData/CloudKit only carry
    // metadata, not the raw auth.json contents. Keep the field on CloudKit's
    // encrypted path as defense in depth for any old rows that still haven't
    // been scrubbed yet.
    @Attribute(.allowsCloudEncryption)
    var authFileContents: String?
    // Legacy CloudKit field kept only for schema compatibility. Real
    // per-device snapshot availability now lives outside SwiftData, so this
    // value should be normalized back to false on startup and ignored by new
    // code paths.
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
    // Widgets and compact surfaces need to distinguish a truly unknown value
    // from a cached fallback so they can preserve the last known bar fill
    // without pretending the data is live.
    var sevenDayDataStatusRaw: String = RateLimitMetricDataStatus.missing.rawValue
    var fiveHourDataStatusRaw: String = RateLimitMetricDataStatus.missing.rawValue
    var sevenDayResetsAt: Date?
    var fiveHourResetsAt: Date?
    var rateLimitsObservedAt: Date?
    var rateLimitDisplayVersion: Int?
    var iconSystemName: String = "key.fill"
    var availabilityRaw: String = StoredAccountAvailability.available.rawValue
    var unavailableReasonRaw: String?
    var unavailableSince: Date?
    var lastAvailabilityCheckAt: Date?

    init(
        id: UUID = UUID(),
        identityKey: String,
        name: String,
        notes: String = "",
        createdAt: Date = .now,
        lastLoginAt: Date? = nil,
        customOrder: Double,
        isPinned: Bool = false,
        authFileContents: String? = nil,
        hasLocalSnapshot: Bool = false,
        authModeRaw: String,
        emailHint: String? = nil,
        accountIdentifier: String? = nil,
        sevenDayLimitUsedPercent: Int? = nil,
        fiveHourLimitUsedPercent: Int? = nil,
        sevenDayDataStatusRaw: String? = nil,
        fiveHourDataStatusRaw: String? = nil,
        sevenDayResetsAt: Date? = nil,
        fiveHourResetsAt: Date? = nil,
        rateLimitsObservedAt: Date? = nil,
        rateLimitDisplayVersion: Int? = 1,
        iconSystemName: String = "key.fill",
        availabilityRaw: String = StoredAccountAvailability.available.rawValue,
        unavailableReasonRaw: String? = nil,
        unavailableSince: Date? = nil,
        lastAvailabilityCheckAt: Date? = nil
    ) {
        self.id = id
        self.identityKey = identityKey
        self.name = name
        self.notes = notes
        self.createdAt = createdAt
        self.lastLoginAt = lastLoginAt
        self.customOrder = customOrder
        self.isPinned = isPinned
        self.authFileContents = authFileContents
        self.hasLocalSnapshot = hasLocalSnapshot
        self.authModeRaw = authModeRaw
        self.emailHint = emailHint
        self.accountIdentifier = accountIdentifier
        self.sevenDayLimitUsedPercent = sevenDayLimitUsedPercent
        self.fiveHourLimitUsedPercent = fiveHourLimitUsedPercent
        self.sevenDayDataStatusRaw = sevenDayDataStatusRaw
            ?? Self.defaultMetricStatusRaw(for: sevenDayLimitUsedPercent)
        self.fiveHourDataStatusRaw = fiveHourDataStatusRaw
            ?? Self.defaultMetricStatusRaw(for: fiveHourLimitUsedPercent)
        self.sevenDayResetsAt = sevenDayResetsAt
        self.fiveHourResetsAt = fiveHourResetsAt
        self.rateLimitsObservedAt = rateLimitsObservedAt
        self.rateLimitDisplayVersion = rateLimitDisplayVersion
        self.iconSystemName = iconSystemName
        self.availabilityRaw = availabilityRaw
        self.unavailableReasonRaw = unavailableReasonRaw
        self.unavailableSince = unavailableSince
        self.lastAvailabilityCheckAt = lastAvailabilityCheckAt
    }

    var availability: StoredAccountAvailability {
        get {
            StoredAccountAvailability(rawValue: availabilityRaw) ?? .available
        }
        set {
            availabilityRaw = newValue.rawValue
        }
    }

    var unavailableReason: StoredAccountUnavailableReason? {
        get {
            guard let unavailableReasonRaw else {
                return nil
            }

            return StoredAccountUnavailableReason(rawValue: unavailableReasonRaw)
        }
        set {
            unavailableReasonRaw = newValue?.rawValue
        }
    }

    var isUnavailable: Bool {
        availability == .unavailableUnauthorized
    }

    var unavailableWarningMessage: String? {
        guard isUnavailable else {
            return nil
        }

        return unavailableWarningMessage(accountName: name)
    }

    func unavailableWarningMessage(accountName: String) -> String {
        let sanitizedName = accountName.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = sanitizedName.isEmpty ? "Unknown Account" : sanitizedName

        return """
        The saved refresh token for “\(displayName)” is no longer valid. To fix this, remove the account from Codex Switcher, then add it again to regenerate the token. To avoid this issue in the future, do not use the “Log out” button in Codex.
        """
    }

    /// Older synced rows may predate explicit data-status tracking. In that
    /// case, preserve the existing value as exact instead of regressing to a
    /// fake "unknown" state just because the additive field was missing.
    var sevenDayDataStatus: RateLimitMetricDataStatus {
        get {
            resolvedMetricStatus(rawValue: sevenDayDataStatusRaw, value: sevenDayLimitUsedPercent)
        }
        set {
            sevenDayDataStatusRaw = newValue.rawValue
        }
    }

    var fiveHourDataStatus: RateLimitMetricDataStatus {
        get {
            resolvedMetricStatus(rawValue: fiveHourDataStatusRaw, value: fiveHourLimitUsedPercent)
        }
        set {
            fiveHourDataStatusRaw = newValue.rawValue
        }
    }

    private static func defaultMetricStatusRaw(for value: Int?) -> String {
        value == nil ? RateLimitMetricDataStatus.missing.rawValue : RateLimitMetricDataStatus.exact.rawValue
    }

    private func resolvedMetricStatus(rawValue: String, value: Int?) -> RateLimitMetricDataStatus {
        guard let status = RateLimitMetricDataStatus(rawValue: rawValue) else {
            return value == nil ? .missing : .exact
        }

        if status == .missing, value != nil {
            return .exact
        }

        return status
    }

    @discardableResult
    func normalizeLegacyLocalOnlyFields() -> Bool {
        guard hasLocalSnapshot else {
            return false
        }

        hasLocalSnapshot = false
        return true
    }
}
