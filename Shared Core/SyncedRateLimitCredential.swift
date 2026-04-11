//
//  SyncedRateLimitCredential.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-11.
//

import CryptoKit
import Foundation

nonisolated enum SyncedRateLimitCredentialError: LocalizedError {
    case unsupportedCredentials

    var errorDescription: String? {
        switch self {
        case .unsupportedCredentials:
            "The saved account does not contain ChatGPT credentials that can fetch live rate limits."
        }
    }
}

/// A minimal credential export for rate-limit reads only.
///
/// Keep this payload intentionally narrow: it should contain only the fields
/// required for the usage API request, not the full auth.json snapshot that the
/// Mac stores locally for switching.
nonisolated struct SyncedRateLimitCredential: Codable, Sendable, Equatable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let identityKey: String
    let authModeRaw: String
    let accountID: String?
    let accessToken: String
    let exportedAt: Date

    init(
        credentials: CodexRateLimitCredentials,
        exportedAt: Date = .now
    ) throws {
        guard
            credentials.authMode != .apiKey,
            let trimmedToken = credentials.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmedToken.isEmpty
        else {
            throw SyncedRateLimitCredentialError.unsupportedCredentials
        }

        self.schemaVersion = Self.currentSchemaVersion
        self.identityKey = credentials.identityKey
        self.authModeRaw = credentials.authMode.rawValue
        self.accountID = credentials.accountID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.accessToken = trimmedToken
        self.exportedAt = exportedAt
    }

    var fingerprint: String {
        let joined = [identityKey, accountID ?? "", accessToken].joined(separator: "|")
        let digest = SHA256.hash(data: Data(joined.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    var rateLimitCredentials: CodexRateLimitCredentials {
        CodexRateLimitCredentials(
            identityKey: identityKey,
            authMode: CodexAuthMode(rawValue: authModeRaw) ?? .chatgpt,
            accountID: accountID,
            accessToken: accessToken,
            idToken: nil
        )
    }

    func encodedJSONString() throws -> String {
        let data = try JSONEncoder().encode(self)
        guard let string = String(data: data, encoding: .utf8) else {
            throw SyncedRateLimitCredentialStoreError.invalidPayload
        }
        return string
    }

    static func decode(jsonString: String) throws -> SyncedRateLimitCredential {
        guard let data = jsonString.data(using: .utf8) else {
            throw SyncedRateLimitCredentialStoreError.invalidPayload
        }

        let credential = try JSONDecoder().decode(SyncedRateLimitCredential.self, from: data)
        guard credential.schemaVersion == currentSchemaVersion else {
            throw SyncedRateLimitCredentialStoreError.invalidPayload
        }

        return credential
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
