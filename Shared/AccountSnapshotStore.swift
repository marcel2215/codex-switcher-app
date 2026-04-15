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
            "That saved account no longer has a stored auth snapshot on this device."
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
    private let sharedAccessGroup: String?
    private let logger: Logger

    init(
        service: String = SharedKeychainSnapshotStore.sharedService,
        accessGroup: String? = CodexSharedAppGroup.identifier,
        logger: Logger = Logger(
            subsystem: CodexSharedApplicationIdentity.mainApplicationBundleIdentifier,
            category: "AccountSnapshotStore"
        )
    ) {
        self.service = service
        let trimmedAccessGroup = accessGroup?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sharedAccessGroup = trimmedAccessGroup?.isEmpty == false ? trimmedAccessGroup : nil
        self.logger = logger
    }

    func saveSnapshot(_ contents: String, forIdentityKey identityKey: String) async throws {
        let normalizedIdentityKey = try normalizedIdentityKey(identityKey)
        guard let data = contents.data(using: .utf8) else {
            throw AccountSnapshotStoreError.invalidEncoding
        }

        try upsertSnapshot(
            data,
            forIdentityKey: normalizedIdentityKey,
            query: sharedLocalQuery(forIdentityKey: normalizedIdentityKey),
            accessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            logPrefix: "Shared keychain"
        )

        do {
            try upsertSnapshot(
                data,
                forIdentityKey: normalizedIdentityKey,
                query: synchronizableQuery(forIdentityKey: normalizedIdentityKey),
                accessible: kSecAttrAccessibleWhenUnlocked,
                logPrefix: "Synchronizable keychain"
            )
        } catch let error as AccountSnapshotStoreError {
            logger.error(
                "Synchronizable keychain save failed for \(normalizedIdentityKey, privacy: .private); the snapshot will stay available only on this device until keychain sync succeeds: \(error.localizedDescription, privacy: .public)"
            )
        }

        pruneLegacySynchronizableSharedSnapshot(forIdentityKey: normalizedIdentityKey)
    }

    func loadSnapshot(forIdentityKey identityKey: String) async throws -> String {
        let normalizedIdentityKey = try normalizedIdentityKey(identityKey)
        if let sharedLocalContents = try loadSnapshotContentsIfPresent(
            forIdentityKey: normalizedIdentityKey,
            query: sharedLocalQuery(forIdentityKey: normalizedIdentityKey)
        ) {
            repairCurrentSnapshotCopies(
                using: sharedLocalContents,
                forIdentityKey: normalizedIdentityKey,
                ensureSharedLocalCopy: false,
                ensureSynchronizableCopy: true
            )
            return sharedLocalContents
        }

        if let synchronizableContents = try loadSnapshotContentsIfPresent(
            forIdentityKey: normalizedIdentityKey,
            query: synchronizableQuery(forIdentityKey: normalizedIdentityKey)
        ) {
            repairCurrentSnapshotCopies(
                using: synchronizableContents,
                forIdentityKey: normalizedIdentityKey,
                ensureSharedLocalCopy: true,
                ensureSynchronizableCopy: false
            )
            return synchronizableContents
        }

        if let legacySynchronizableContents = try loadLegacySynchronizableSharedSnapshotIfPresent(
            forIdentityKey: normalizedIdentityKey
        ) {
            repairCurrentSnapshotCopies(
                using: legacySynchronizableContents,
                forIdentityKey: normalizedIdentityKey,
                ensureSharedLocalCopy: true,
                ensureSynchronizableCopy: true
            )
            return legacySynchronizableContents
        }

        throw AccountSnapshotStoreError.missingSnapshot
    }

    func deleteSnapshot(forIdentityKey identityKey: String) async throws {
        let normalizedIdentityKey = try normalizedIdentityKey(identityKey)
        try deleteSnapshotIfPresent(
            matching: sharedLocalQuery(forIdentityKey: normalizedIdentityKey),
            logPrefix: "Shared keychain"
        )
        try deleteSnapshotIfPresent(
            matching: synchronizableQuery(forIdentityKey: normalizedIdentityKey),
            logPrefix: "Synchronizable keychain"
        )
        try deleteLegacySynchronizableSharedSnapshotIfPresent(forIdentityKey: normalizedIdentityKey)
    }

    func containsSnapshot(forIdentityKey identityKey: String) async -> Bool {
        do {
            _ = try await loadSnapshot(forIdentityKey: identityKey)
            return true
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

    private func loadSnapshotContentsIfPresent(
        forIdentityKey identityKey: String,
        query: [String: Any]
    ) throws -> String? {
        var dataQuery = query
        dataQuery[kSecReturnData as String] = true
        dataQuery[kSecMatchLimit as String] = kSecMatchLimitOne

        do {
            return try decodeSnapshotContents(from: dataQuery)
        } catch AccountSnapshotStoreError.missingSnapshot {
            return nil
        }
    }

    /// Store a device-local app-group copy for extensions and a synchronizable
    /// copy for the main app across the user's devices.
    private func repairCurrentSnapshotCopies(
        using contents: String,
        forIdentityKey identityKey: String,
        ensureSharedLocalCopy: Bool,
        ensureSynchronizableCopy: Bool
    ) {
        guard let data = contents.data(using: .utf8) else {
            logger.error(
                "Couldn't repair keychain storage for \(identityKey, privacy: .private) because the snapshot couldn't be re-encoded as UTF-8."
            )
            return
        }

        if ensureSharedLocalCopy {
            do {
                try upsertSnapshot(
                    data,
                    forIdentityKey: identityKey,
                    query: sharedLocalQuery(forIdentityKey: identityKey),
                    accessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                    logPrefix: "Shared keychain"
                )
            } catch {
                logger.error(
                    "Couldn't repair the device-local shared snapshot for \(identityKey, privacy: .private): \(String(describing: error), privacy: .private)"
                )
            }
        }

        if ensureSynchronizableCopy {
            do {
                try upsertSnapshot(
                    data,
                    forIdentityKey: identityKey,
                    query: synchronizableQuery(forIdentityKey: identityKey),
                    accessible: kSecAttrAccessibleWhenUnlocked,
                    logPrefix: "Synchronizable keychain"
                )
            } catch {
                logger.error(
                    "Couldn't repair the synchronizable snapshot for \(identityKey, privacy: .private): \(String(describing: error), privacy: .private)"
                )
            }
        }

        pruneLegacySynchronizableSharedSnapshot(forIdentityKey: identityKey)
    }

    private func upsertSnapshot(
        _ data: Data,
        forIdentityKey identityKey: String,
        query: [String: Any],
        accessible: CFString,
        logPrefix: String
    ) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessible,
        ]

        switch SecItemCopyMatching(query as CFDictionary, nil) {
        case errSecItemNotFound:
            var item = query
            attributes.forEach { item[$0.key] = $0.value }

            let status = SecItemAdd(item as CFDictionary, nil)
            guard status == errSecSuccess else {
                logger.error("\(logPrefix, privacy: .public) add failed for \(identityKey, privacy: .private) with status \(status, privacy: .public)")
                throw AccountSnapshotStoreError.unexpectedStatus(status)
            }

        case errSecSuccess:
            let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard status == errSecSuccess else {
                logger.error("\(logPrefix, privacy: .public) update failed for \(identityKey, privacy: .private) with status \(status, privacy: .public)")
                throw AccountSnapshotStoreError.unexpectedStatus(status)
            }

        case let status:
            logger.error("\(logPrefix, privacy: .public) lookup failed for \(identityKey, privacy: .private) with status \(status, privacy: .public)")
            throw AccountSnapshotStoreError.unexpectedStatus(status)
        }
    }

    private func baseQuery(
        forIdentityKey identityKey: String,
        accessGroup: String?
    ) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrService as String: service,
            kSecAttrAccount as String: identityKey,
        ]

        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        return query
    }

    private func synchronizableQuery(forIdentityKey identityKey: String) -> [String: Any] {
        var query = baseQuery(forIdentityKey: identityKey, accessGroup: nil)
        query[kSecAttrSynchronizable as String] = kCFBooleanTrue
        return query
    }

    /// The device-local copy stays in the app-group keychain so app intents,
    /// widgets, and the main app can all access the snapshot on this device
    /// without depending on iCloud Keychain state.
    private func sharedLocalQuery(forIdentityKey identityKey: String) -> [String: Any] {
        var query = baseQuery(forIdentityKey: identityKey, accessGroup: sharedAccessGroup)
        query[kSecAttrSynchronizable as String] = kCFBooleanFalse
        return query
    }

    /// The synchronizable copy intentionally uses the app's default access
    /// group so the primary app can pick it up on another device even when the
    /// device-local app-group copy hasn't been recreated there yet.
    private func legacySharedSynchronizableQuery(forIdentityKey identityKey: String) -> [String: Any]? {
        guard let sharedAccessGroup else {
            return nil
        }

        var query = baseQuery(forIdentityKey: identityKey, accessGroup: sharedAccessGroup)
        query[kSecAttrSynchronizable as String] = kCFBooleanTrue
        return query
    }

    private func loadLegacySynchronizableSharedSnapshotIfPresent(
        forIdentityKey identityKey: String
    ) throws -> String? {
        guard let legacyQuery = legacySharedSynchronizableQuery(forIdentityKey: identityKey) else {
            return nil
        }

        return try loadSnapshotContentsIfPresent(
            forIdentityKey: identityKey,
            query: legacyQuery
        )
    }

    private func deleteSnapshotIfPresent(
        matching query: [String: Any],
        logPrefix: String
    ) throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            logger.error("\(logPrefix, privacy: .public) delete failed with status \(status, privacy: .public)")
            throw AccountSnapshotStoreError.unexpectedStatus(status)
        }
    }

    private func deleteLegacySynchronizableSharedSnapshotIfPresent(
        forIdentityKey identityKey: String
    ) throws {
        guard let legacyQuery = legacySharedSynchronizableQuery(forIdentityKey: identityKey) else {
            return
        }

        try deleteSnapshotIfPresent(
            matching: legacyQuery,
            logPrefix: "Legacy synchronizable keychain"
        )
    }

    private func pruneLegacySynchronizableSharedSnapshot(forIdentityKey identityKey: String) {
        do {
            try deleteLegacySynchronizableSharedSnapshotIfPresent(forIdentityKey: identityKey)
        } catch {
            logger.error(
                "Couldn't prune legacy synchronizable shared snapshot for \(identityKey, privacy: .private): \(String(describing: error), privacy: .private)"
            )
        }
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
