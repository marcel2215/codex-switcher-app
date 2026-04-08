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
        self.iconSystemName = iconSystemName
    }
}
