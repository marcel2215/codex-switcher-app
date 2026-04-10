//
//  AccountSnapshotStore.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-11.
//

import Foundation
import OSLog
import Security

nonisolated protocol AccountSnapshotStoring: Sendable {
    func saveSnapshot(_ contents: String, forIdentityKey identityKey: String) async throws
    func loadSnapshot(forIdentityKey identityKey: String) async throws -> String
    func deleteSnapshot(forIdentityKey identityKey: String) async throws
    func containsSnapshot(forIdentityKey identityKey: String) async -> Bool
    func migrateLegacySnapshotIfNeeded(
        fromLegacyAccountID accountID: UUID,
        toIdentityKey identityKey: String
    ) async throws -> Bool
}

enum AccountSnapshotStoreError: LocalizedError, Equatable {
    case invalidIdentityKey
    case missingSnapshot
    case invalidEncoding
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidIdentityKey:
            "That saved account no longer has a valid identity key."
        case .missingSnapshot:
            "That saved account no longer has a stored auth snapshot on this Mac."
        case .invalidEncoding:
            "The stored auth snapshot is no longer valid UTF-8 text."
        case let .unexpectedStatus(status):
            "Keychain access failed with status \(status)."
        }
    }
}

actor SharedKeychainSnapshotStore: AccountSnapshotStoring {
    nonisolated static let sharedService = "com.marcel2215.codexswitcher.authSnapshots"
    nonisolated static let legacyService = CodexSharedApplicationIdentity.mainApplicationBundleIdentifier + ".accountSecrets"

    private let service: String
    private let accessGroup: String
    private let logger: Logger

    init(
        service: String = SharedKeychainSnapshotStore.sharedService,
        accessGroup: String = CodexSharedAppGroup.identifier,
        logger: Logger = Logger(
            subsystem: CodexSharedApplicationIdentity.mainApplicationBundleIdentifier,
            category: "AccountSnapshotStore"
        )
    ) {
        self.service = service
        self.accessGroup = accessGroup
        self.logger = logger
    }

    func saveSnapshot(_ contents: String, forIdentityKey identityKey: String) async throws {
        let normalizedIdentityKey = try normalizedIdentityKey(identityKey)
        guard let data = contents.data(using: .utf8) else {
            throw AccountSnapshotStoreError.invalidEncoding
        }

        let query = baseQuery(forIdentityKey: normalizedIdentityKey)
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
                throw AccountSnapshotStoreError.unexpectedStatus(status)
            }

        case errSecSuccess:
            let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard status == errSecSuccess else {
                logger.error("Keychain update failed with status \(status, privacy: .public)")
                throw AccountSnapshotStoreError.unexpectedStatus(status)
            }

        case let status:
            logger.error("Keychain lookup failed with status \(status, privacy: .public)")
            throw AccountSnapshotStoreError.unexpectedStatus(status)
        }
    }

    func loadSnapshot(forIdentityKey identityKey: String) async throws -> String {
        let normalizedIdentityKey = try normalizedIdentityKey(identityKey)
        var query = baseQuery(forIdentityKey: normalizedIdentityKey)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        return try decodeSnapshotContents(from: query)
    }

    func deleteSnapshot(forIdentityKey identityKey: String) async throws {
        let normalizedIdentityKey = try normalizedIdentityKey(identityKey)
        let status = SecItemDelete(baseQuery(forIdentityKey: normalizedIdentityKey) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            logger.error("Keychain delete failed with status \(status, privacy: .public)")
            throw AccountSnapshotStoreError.unexpectedStatus(status)
        }
    }

    func containsSnapshot(forIdentityKey identityKey: String) async -> Bool {
        do {
            let normalizedIdentityKey = try normalizedIdentityKey(identityKey)
            var query = baseQuery(forIdentityKey: normalizedIdentityKey)
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            query[kSecReturnAttributes as String] = true
            return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
        } catch {
            return false
        }
    }

    func migrateLegacySnapshotIfNeeded(
        fromLegacyAccountID accountID: UUID,
        toIdentityKey identityKey: String
    ) async throws -> Bool {
        let normalizedIdentityKey = try normalizedIdentityKey(identityKey)
        let legacyQuery = legacyQuery(forLegacyAccountID: accountID)

        if await containsSnapshot(forIdentityKey: normalizedIdentityKey) {
            try deleteLegacySnapshot(forLegacyAccountID: accountID)
            return false
        }

        let legacyContents: String
        do {
            legacyContents = try decodeSnapshotContents(from: legacyQuery)
        } catch AccountSnapshotStoreError.missingSnapshot {
            return false
        }

        try await saveSnapshot(legacyContents, forIdentityKey: normalizedIdentityKey)
        try deleteLegacySnapshot(forLegacyAccountID: accountID)
        return true
    }

    private func deleteLegacySnapshot(forLegacyAccountID accountID: UUID) throws {
        let status = SecItemDelete(legacyQuery(forLegacyAccountID: accountID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            logger.error("Legacy keychain delete failed with status \(status, privacy: .public)")
            throw AccountSnapshotStoreError.unexpectedStatus(status)
        }
    }

    private func decodeSnapshotContents(from query: [String: Any]) throws -> String {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw AccountSnapshotStoreError.invalidEncoding
            }

            guard let contents = String(data: data, encoding: .utf8) else {
                throw AccountSnapshotStoreError.invalidEncoding
            }

            return contents

        case errSecItemNotFound:
            throw AccountSnapshotStoreError.missingSnapshot

        default:
            logger.error("Keychain read failed with status \(status, privacy: .public)")
            throw AccountSnapshotStoreError.unexpectedStatus(status)
        }
    }

    private func baseQuery(forIdentityKey identityKey: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrService as String: service,
            kSecAttrAccount as String: identityKey,
            kSecAttrAccessGroup as String: accessGroup,
        ]
    }

    private func legacyQuery(forLegacyAccountID accountID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.legacyService,
            kSecAttrAccount as String: accountID.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
    }

    private func normalizedIdentityKey(_ identityKey: String) throws -> String {
        let normalizedIdentityKey = identityKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedIdentityKey.isEmpty else {
            throw AccountSnapshotStoreError.invalidIdentityKey
        }

        return normalizedIdentityKey
    }
}
