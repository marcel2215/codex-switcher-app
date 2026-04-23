//
//  StoredAccountCloudSyncSupport.swift
//  Codex Switcher
//
//  Created by Marcel Kwiatkowski on 2026-04-23.
//

import Foundation
import OSLog
import SwiftData

@MainActor
enum StoredAccountCloudSyncSupport {
    private enum StorageKey {
        static let syncedRateLimitCredentialAccessibilityMigrationPrefix =
            "stored-account-cloud-sync-support.synced-rate-limit-credential-accessibility."
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "CodexSwitcher",
        category: "StoredAccountCloudSyncSupport"
    )

    @discardableResult
    static func update(_ account: StoredAccount, from snapshot: SharedCodexAuthSnapshot) -> Bool {
        var didChange = account.normalizeLegacyLocalOnlyFields()

        if account.identityKey != snapshot.identityKey {
            account.identityKey = snapshot.identityKey
            didChange = true
        }

        if account.authModeRaw != snapshot.authMode.rawValue {
            account.authModeRaw = snapshot.authMode.rawValue
            didChange = true
        }

        if account.emailHint != snapshot.email {
            account.emailHint = snapshot.email
            didChange = true
        }

        if account.accountIdentifier != snapshot.accountIdentifier {
            account.accountIdentifier = snapshot.accountIdentifier
            didChange = true
        }

        if account.iconSystemName.isEmpty {
            account.iconSystemName = AccountIconOption.defaultOption.systemName
            didChange = true
        }

        return didChange
    }

    @discardableResult
    static func exportSyncedRateLimitCredentialIfNeeded(
        from rawContents: String,
        expectedIdentityKey: String,
        in modelContext: ModelContext,
        syncedRateLimitCredentialStore: SyncedRateLimitCredentialStoring,
        excludingAccountIDsForDelete: Set<UUID> = [],
        forceRewrite: Bool = false,
        logger: Logger = Self.logger
    ) async -> Bool {
        let normalizedIdentityKey = normalizedIdentityKey(expectedIdentityKey)
        guard !normalizedIdentityKey.isEmpty else {
            return false
        }

        do {
            let credentials = try SharedCodexAuthFile.parseRateLimitCredentials(contents: rawContents)
            guard
                credentials.identityKey == normalizedIdentityKey,
                credentials.authMode != .apiKey,
                credentials.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            else {
                await deleteSyncedRateLimitCredentialIfUnused(
                    identityKey: normalizedIdentityKey,
                    in: modelContext,
                    syncedRateLimitCredentialStore: syncedRateLimitCredentialStore,
                    excludingAccountIDs: excludingAccountIDsForDelete,
                    logger: logger
                )
                return false
            }

            let syncedCredential: SyncedRateLimitCredential
            do {
                syncedCredential = try SyncedRateLimitCredential(credentials: credentials)
            } catch {
                await deleteSyncedRateLimitCredentialIfUnused(
                    identityKey: normalizedIdentityKey,
                    in: modelContext,
                    syncedRateLimitCredentialStore: syncedRateLimitCredentialStore,
                    excludingAccountIDs: excludingAccountIDsForDelete,
                    logger: logger
                )
                return false
            }

            let existingCredential = try? await syncedRateLimitCredentialStore.load(
                forIdentityKey: normalizedIdentityKey
            )
            guard forceRewrite || existingCredential?.fingerprint != syncedCredential.fingerprint else {
                return false
            }

            do {
                try await syncedRateLimitCredentialStore.save(syncedCredential)
            } catch {
                logger.error(
                    "Couldn't save synced rate-limit credential for \(normalizedIdentityKey, privacy: .private): \(String(describing: error), privacy: .private)"
                )
                return false
            }

            return true
        } catch {
            logger.error(
                "Couldn't export synced rate-limit credential for \(normalizedIdentityKey, privacy: .private): \(String(describing: error), privacy: .private)"
            )
            await deleteSyncedRateLimitCredentialIfUnused(
                identityKey: normalizedIdentityKey,
                in: modelContext,
                syncedRateLimitCredentialStore: syncedRateLimitCredentialStore,
                excludingAccountIDs: excludingAccountIDsForDelete,
                logger: logger
            )
            return false
        }
    }

    static func shouldForceRewriteSyncedRateLimitCredential(
        for identityKey: String,
        userDefaults: UserDefaults = .standard
    ) -> Bool {
        let normalizedIdentityKey = normalizedIdentityKey(identityKey)
        guard !normalizedIdentityKey.isEmpty else {
            return false
        }

        return userDefaults.bool(
            forKey: syncedRateLimitCredentialAccessibilityMigrationKey(for: normalizedIdentityKey)
        ) == false
    }

    static func markSyncedRateLimitCredentialAccessibilityMigrated(
        for identityKey: String,
        userDefaults: UserDefaults = .standard
    ) {
        let normalizedIdentityKey = normalizedIdentityKey(identityKey)
        guard !normalizedIdentityKey.isEmpty else {
            return
        }

        userDefaults.set(
            true,
            forKey: syncedRateLimitCredentialAccessibilityMigrationKey(for: normalizedIdentityKey)
        )
    }

    static func deleteArtifactsIfUnused(
        identityKey: String,
        in modelContext: ModelContext,
        snapshotStore: AccountSnapshotStoring,
        syncedRateLimitCredentialStore: SyncedRateLimitCredentialStoring,
        excludingAccountIDs: Set<UUID> = [],
        logger: Logger = Self.logger
    ) async {
        let normalizedIdentityKey = normalizedIdentityKey(identityKey)
        guard !normalizedIdentityKey.isEmpty else {
            return
        }

        do {
            let remainingIdentityKeys = Set(
                try modelContext.fetch(FetchDescriptor<StoredAccount>())
                    .filter { !excludingAccountIDs.contains($0.id) }
                    .map(\.identityKey)
                    .map(normalizedIdentityKey(_:))
                    .filter { !$0.isEmpty }
            )

            guard !remainingIdentityKeys.contains(normalizedIdentityKey) else {
                return
            }
        } catch {
            logger.error(
                "Couldn't inspect remaining accounts before deleting artifacts for \(normalizedIdentityKey, privacy: .private): \(String(describing: error), privacy: .private)"
            )
            return
        }

        do {
            try await snapshotStore.deleteSnapshot(forIdentityKey: normalizedIdentityKey)
        } catch {
            logger.error(
                "Couldn't delete snapshot for \(normalizedIdentityKey, privacy: .private): \(String(describing: error), privacy: .private)"
            )
        }

        do {
            try await syncedRateLimitCredentialStore.delete(forIdentityKey: normalizedIdentityKey)
        } catch {
            logger.error(
                "Couldn't delete synced rate-limit credential for \(normalizedIdentityKey, privacy: .private): \(String(describing: error), privacy: .private)"
            )
        }
    }

    @discardableResult
    static func reconcileDuplicateAccountsIfNeeded(
        in modelContext: ModelContext,
        logger: Logger = Self.logger
    ) async -> Bool {
        do {
            let duplicateGroups = Dictionary(
                grouping: try modelContext.fetch(FetchDescriptor<StoredAccount>()).filter {
                    !normalizedIdentityKey($0.identityKey).isEmpty
                },
                by: { normalizedIdentityKey($0.identityKey) }
            ).values.filter { $0.count > 1 }

            guard !duplicateGroups.isEmpty else {
                return false
            }

            var didChange = false

            for group in duplicateGroups {
                let sortedGroup = group.sorted { lhs, rhs in
                    if lhs.createdAt != rhs.createdAt {
                        return lhs.createdAt < rhs.createdAt
                    }

                    return lhs.id.uuidString < rhs.id.uuidString
                }

                guard let survivor = sortedGroup.first else {
                    continue
                }

                for duplicate in sortedGroup.dropFirst() {
                    didChange = mergeDuplicateAccount(duplicate, into: survivor) || didChange
                    modelContext.delete(duplicate)
                    didChange = true
                }
            }

            return didChange
        } catch {
            logger.error("Duplicate account reconciliation failed: \(String(describing: error), privacy: .private)")
            return false
        }
    }

    private static func deleteSyncedRateLimitCredentialIfUnused(
        identityKey: String,
        in modelContext: ModelContext,
        syncedRateLimitCredentialStore: SyncedRateLimitCredentialStoring,
        excludingAccountIDs: Set<UUID> = [],
        logger: Logger = Self.logger
    ) async {
        let normalizedIdentityKey = normalizedIdentityKey(identityKey)
        guard !normalizedIdentityKey.isEmpty else {
            return
        }

        do {
            let remainingIdentityKeys = Set(
                try modelContext.fetch(FetchDescriptor<StoredAccount>())
                    .filter { !excludingAccountIDs.contains($0.id) }
                    .map(\.identityKey)
                    .map(normalizedIdentityKey(_:))
                    .filter { !$0.isEmpty }
            )

            guard !remainingIdentityKeys.contains(normalizedIdentityKey) else {
                return
            }

            try await syncedRateLimitCredentialStore.delete(forIdentityKey: normalizedIdentityKey)
        } catch {
            logger.error(
                "Couldn't delete synced rate-limit credential for \(normalizedIdentityKey, privacy: .private): \(String(describing: error), privacy: .private)"
            )
        }
    }

    private static func mergeDuplicateAccount(_ duplicate: StoredAccount, into survivor: StoredAccount) -> Bool {
        var didChange = false

        if survivor.createdAt > duplicate.createdAt {
            survivor.createdAt = duplicate.createdAt
            didChange = true
        }

        if survivor.customOrder > duplicate.customOrder {
            survivor.customOrder = duplicate.customOrder
            didChange = true
        }

        if (duplicate.lastLoginAt ?? .distantPast) > (survivor.lastLoginAt ?? .distantPast) {
            survivor.lastLoginAt = duplicate.lastLoginAt
            didChange = true
        }

        if !survivor.isPinned && duplicate.isPinned {
            survivor.isPinned = true
            didChange = true
        }

        if (duplicate.rateLimitsObservedAt ?? .distantPast) > (survivor.rateLimitsObservedAt ?? .distantPast) {
            survivor.rateLimitsObservedAt = duplicate.rateLimitsObservedAt
            survivor.sevenDayLimitUsedPercent = duplicate.sevenDayLimitUsedPercent
            survivor.fiveHourLimitUsedPercent = duplicate.fiveHourLimitUsedPercent
            survivor.sevenDayResetsAt = duplicate.sevenDayResetsAt
            survivor.fiveHourResetsAt = duplicate.fiveHourResetsAt
            survivor.sevenDayDataStatusRaw = duplicate.sevenDayDataStatusRaw
            survivor.fiveHourDataStatusRaw = duplicate.fiveHourDataStatusRaw
            survivor.rateLimitDisplayVersion = duplicate.rateLimitDisplayVersion
            didChange = true
        }

        if survivor.rateLimitDisplayVersion == nil, duplicate.rateLimitDisplayVersion != nil {
            survivor.rateLimitDisplayVersion = duplicate.rateLimitDisplayVersion
            didChange = true
        }

        if
            (survivor.name.isEmpty || (isGeneratedAccountName(survivor.name) && !isGeneratedAccountName(duplicate.name))),
            !duplicate.name.isEmpty
        {
            survivor.name = duplicate.name
            didChange = true
        }

        if survivor.emailHint == nil, let duplicateEmail = duplicate.emailHint {
            survivor.emailHint = duplicateEmail
            didChange = true
        }

        if survivor.accountIdentifier == nil, let duplicateAccountIdentifier = duplicate.accountIdentifier {
            survivor.accountIdentifier = duplicateAccountIdentifier
            didChange = true
        }

        if survivor.iconSystemName == AccountIconOption.defaultOption.systemName,
           duplicate.iconSystemName != AccountIconOption.defaultOption.systemName {
            survivor.iconSystemName = duplicate.iconSystemName
            didChange = true
        }

        return didChange
    }

    private static func syncedRateLimitCredentialAccessibilityMigrationKey(for identityKey: String) -> String {
        StorageKey.syncedRateLimitCredentialAccessibilityMigrationPrefix + identityKey
    }

    private static func normalizedIdentityKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isGeneratedAccountName(_ name: String) -> Bool {
        generatedAccountIndex(from: name) != nil
    }

    private static func generatedAccountIndex(from name: String) -> Int? {
        guard name.hasPrefix("Account ") else {
            return nil
        }

        return Int(name.dropFirst("Account ".count))
    }
}
