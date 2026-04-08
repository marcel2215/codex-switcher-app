//
//  AccountSecretStore.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-08.
//

import Foundation
import OSLog
import Security

protocol AccountSecretStoring: Sendable {
    func saveSecret(_ contents: String, for accountID: UUID) async throws
    func loadSecret(for accountID: UUID) async throws -> String
    func deleteSecret(for accountID: UUID) async throws
}

enum AccountSecretStoreError: LocalizedError, Equatable {
    case missingSecret
    case invalidEncoding
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .missingSecret:
            "That saved account no longer has a stored auth snapshot."
        case .invalidEncoding:
            "The stored auth snapshot is no longer valid UTF-8 text."
        case let .unexpectedStatus(status):
            "Keychain access failed with status \(status)."
        }
    }
}

actor KeychainAccountSecretStore: AccountSecretStoring {
    private let service: String
    private let logger: Logger

    init(bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "CodexSwitcher") {
        self.service = bundleIdentifier + ".accountSecrets"
        self.logger = Logger(subsystem: bundleIdentifier, category: "AccountSecretStore")
    }

    /// Mirrors each verbatim auth.json snapshot into the local keychain.
    /// SwiftData keeps the cross-device iCloud-synced copy, while Keychain
    /// gives the current Mac a local fallback if sync is delayed.
    func saveSecret(_ contents: String, for accountID: UUID) async throws {
        guard let data = contents.data(using: .utf8) else {
            throw AccountSecretStoreError.invalidEncoding
        }

        let query = baseQuery(for: accountID)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        switch SecItemCopyMatching(query as CFDictionary, nil) {
        case errSecItemNotFound:
            var item = query
            attributes.forEach { item[$0.key] = $0.value }

            let status = SecItemAdd(item as CFDictionary, nil)
            guard status == errSecSuccess else {
                logger.error("Keychain add failed with status \(status, privacy: .public)")
                throw AccountSecretStoreError.unexpectedStatus(status)
            }

        case errSecSuccess:
            let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard status == errSecSuccess else {
                logger.error("Keychain update failed with status \(status, privacy: .public)")
                throw AccountSecretStoreError.unexpectedStatus(status)
            }

        case let status:
            logger.error("Keychain lookup failed with status \(status, privacy: .public)")
            throw AccountSecretStoreError.unexpectedStatus(status)
        }
    }

    func loadSecret(for accountID: UUID) async throws -> String {
        var query = baseQuery(for: accountID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw AccountSecretStoreError.invalidEncoding
            }

            guard let contents = String(data: data, encoding: .utf8) else {
                throw AccountSecretStoreError.invalidEncoding
            }

            return contents

        case errSecItemNotFound:
            throw AccountSecretStoreError.missingSecret

        default:
            logger.error("Keychain read failed with status \(status, privacy: .public)")
            throw AccountSecretStoreError.unexpectedStatus(status)
        }
    }

    func deleteSecret(for accountID: UUID) async throws {
        let status = SecItemDelete(baseQuery(for: accountID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            logger.error("Keychain delete failed with status \(status, privacy: .public)")
            throw AccountSecretStoreError.unexpectedStatus(status)
        }
    }

    private func baseQuery(for accountID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID.uuidString,
        ]
    }
}
