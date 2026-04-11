//
//  SyncedRateLimitCredentialStore.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-11.
//

import Foundation
import OSLog
import Security

nonisolated protocol SyncedRateLimitCredentialStoring: Sendable {
    func save(_ credential: SyncedRateLimitCredential) async throws
    func load(forIdentityKey identityKey: String) async throws -> SyncedRateLimitCredential
    func delete(forIdentityKey identityKey: String) async throws
    func containsCredential(forIdentityKey identityKey: String) async -> Bool
}

nonisolated enum SyncedRateLimitCredentialStoreError: LocalizedError, Equatable {
    case invalidIdentityKey
    case missingCredential
    case invalidPayload
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidIdentityKey:
            "The saved account has no valid identity key."
        case .missingCredential:
            "No synced rate-limit credential exists for that account."
        case .invalidPayload:
            "The synced rate-limit credential payload is invalid."
        case let .unexpectedStatus(status):
            "Keychain access failed with status \(status)."
        }
    }
}

actor SyncedRateLimitCredentialStore: SyncedRateLimitCredentialStoring {
    private nonisolated static let service = "com.marcel2215.codexswitcher.syncedRateLimitCredentials"

    private let accessGroup: String?
    private let logger: Logger

    init(
        accessGroup: String? = nil,
        logger: Logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "CodexSwitcher",
            category: "SyncedRateLimitCredentialStore"
        )
    ) {
        self.accessGroup = accessGroup
        self.logger = logger
    }

    func save(_ credential: SyncedRateLimitCredential) async throws {
        let identityKey = try normalizedIdentityKey(credential.identityKey)
        let data = try JSONEncoder().encode(credential)

        let query = baseQuery(forIdentityKey: identityKey)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]

        switch SecItemCopyMatching(query as CFDictionary, nil) {
        case errSecItemNotFound:
            var item = query
            attributes.forEach { item[$0.key] = $0.value }

            let status = SecItemAdd(item as CFDictionary, nil)
            guard status == errSecSuccess else {
                logger.error("Keychain add failed with status \(status, privacy: .public)")
                throw SyncedRateLimitCredentialStoreError.unexpectedStatus(status)
            }

        case errSecSuccess:
            let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard status == errSecSuccess else {
                logger.error("Keychain update failed with status \(status, privacy: .public)")
                throw SyncedRateLimitCredentialStoreError.unexpectedStatus(status)
            }

        case let status:
            logger.error("Keychain lookup failed with status \(status, privacy: .public)")
            throw SyncedRateLimitCredentialStoreError.unexpectedStatus(status)
        }
    }

    func load(forIdentityKey identityKey: String) async throws -> SyncedRateLimitCredential {
        var query = baseQuery(forIdentityKey: try normalizedIdentityKey(identityKey))
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw SyncedRateLimitCredentialStoreError.invalidPayload
            }

            do {
                let credential = try JSONDecoder().decode(SyncedRateLimitCredential.self, from: data)
                guard credential.schemaVersion == SyncedRateLimitCredential.currentSchemaVersion else {
                    throw SyncedRateLimitCredentialStoreError.invalidPayload
                }
                return credential
            } catch let error as SyncedRateLimitCredentialStoreError {
                throw error
            } catch {
                throw SyncedRateLimitCredentialStoreError.invalidPayload
            }

        case errSecItemNotFound:
            throw SyncedRateLimitCredentialStoreError.missingCredential

        default:
            logger.error("Keychain read failed with status \(status, privacy: .public)")
            throw SyncedRateLimitCredentialStoreError.unexpectedStatus(status)
        }
    }

    func delete(forIdentityKey identityKey: String) async throws {
        let status = SecItemDelete(
            baseQuery(forIdentityKey: try normalizedIdentityKey(identityKey)) as CFDictionary
        )

        guard status == errSecSuccess || status == errSecItemNotFound else {
            logger.error("Keychain delete failed with status \(status, privacy: .public)")
            throw SyncedRateLimitCredentialStoreError.unexpectedStatus(status)
        }
    }

    func containsCredential(forIdentityKey identityKey: String) async -> Bool {
        do {
            var query = baseQuery(forIdentityKey: try normalizedIdentityKey(identityKey))
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            query[kSecReturnAttributes as String] = true
            return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
        } catch {
            return false
        }
    }

    private func baseQuery(forIdentityKey identityKey: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: identityKey,
            kSecAttrSynchronizable as String: kCFBooleanTrue as Any,
        ]
        .merging(accessGroup.map { [kSecAttrAccessGroup as String: $0] } ?? [:]) { current, _ in current }
    }

    private func normalizedIdentityKey(_ identityKey: String) throws -> String {
        let trimmed = identityKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SyncedRateLimitCredentialStoreError.invalidIdentityKey
        }

        return trimmed
    }
}
