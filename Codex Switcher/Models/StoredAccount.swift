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
    var identityKey: String = ""
    var name: String = ""
    var createdAt: Date = Date()
    var lastLoginAt: Date?
    var customOrder: Double = 0

    // Stores the full auth.json snapshot so SwiftData + CloudKit can sync
    // saved accounts across devices. The controller also mirrors the same
    // value into the local Keychain as a best-effort device-local cache.
    var authFileContents: String?
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
