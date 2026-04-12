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
    var sevenDayResetsAt: Date?
    var fiveHourResetsAt: Date?
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
        hasLocalSnapshot: Bool = false,
        authModeRaw: String,
        emailHint: String? = nil,
        accountIdentifier: String? = nil,
        sevenDayLimitUsedPercent: Int? = nil,
        fiveHourLimitUsedPercent: Int? = nil,
        sevenDayResetsAt: Date? = nil,
        fiveHourResetsAt: Date? = nil,
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
        self.hasLocalSnapshot = hasLocalSnapshot
        self.authModeRaw = authModeRaw
        self.emailHint = emailHint
        self.accountIdentifier = accountIdentifier
        self.sevenDayLimitUsedPercent = sevenDayLimitUsedPercent
        self.fiveHourLimitUsedPercent = fiveHourLimitUsedPercent
        self.sevenDayResetsAt = sevenDayResetsAt
        self.fiveHourResetsAt = fiveHourResetsAt
        self.rateLimitsObservedAt = rateLimitsObservedAt
        self.rateLimitDisplayVersion = rateLimitDisplayVersion
        self.iconSystemName = iconSystemName
    }
}
