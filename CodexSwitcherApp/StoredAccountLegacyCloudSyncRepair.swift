//
//  StoredAccountLegacyCloudSyncRepair.swift
//  Codex Switcher
//
//  Created by Marcel Kwiatkowski on 2026-04-15.
//

import Foundation
import OSLog
import SwiftData

@MainActor
enum StoredAccountLegacyCloudSyncRepair {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "CodexSwitcher",
        category: "StoredAccountLegacyCloudSyncRepair"
    )

    /// `hasLocalSnapshot` used to mirror device-local keychain availability into
    /// the CloudKit-backed account row. That value can legitimately differ per
    /// device, so leaving it in the synced record causes cross-device churn and
    /// can overwrite real metadata edits. Keep the column for schema
    /// compatibility, but normalize old rows back to a shared false value.
    @discardableResult
    static func normalizeLocalOnlyFieldsIfNeeded(in modelContext: ModelContext) throws -> Bool {
        let accounts = try modelContext.fetch(FetchDescriptor<StoredAccount>())
        var didChange = false

        for account in accounts {
            didChange = account.normalizeLegacyLocalOnlyFields() || didChange
        }

        if didChange {
            try modelContext.save()
        }

        return didChange
    }

    @discardableResult
    static func run(
        in modelContext: ModelContext,
        snapshotStore: AccountSnapshotStoring = SharedKeychainSnapshotStore(),
        syncedRateLimitCredentialStore: SyncedRateLimitCredentialStoring = SyncedRateLimitCredentialStore(),
        logger: Logger = Self.logger
    ) async throws -> Bool {
        let accounts = try modelContext.fetch(FetchDescriptor<StoredAccount>())
        var didChange = false

        for account in accounts {
            didChange = account.normalizeLegacyLocalOnlyFields() || didChange
            didChange = await migrateLegacySnapshotIfNeeded(
                for: account,
                in: modelContext,
                snapshotStore: snapshotStore,
                syncedRateLimitCredentialStore: syncedRateLimitCredentialStore,
                logger: logger
            ) || didChange

            guard let storedContents = await bestAvailableSnapshotContents(
                for: account,
                snapshotStore: snapshotStore,
                logger: logger
            ) else {
                continue
            }

            do {
                let snapshot = try SharedCodexAuthFile.parse(contents: storedContents)
                didChange = StoredAccountCloudSyncSupport.update(account, from: snapshot) || didChange
                if account.authFileContents != nil {
                    account.authFileContents = nil
                    didChange = true
                }
            } catch {
                logger.error(
                    "Stored snapshot reconciliation failed for account \(account.id.uuidString, privacy: .public): \(String(describing: error), privacy: .private)"
                )
            }
        }

        didChange = await StoredAccountCloudSyncSupport.reconcileDuplicateAccountsIfNeeded(
            in: modelContext,
            logger: logger
        ) || didChange

        if didChange {
            try modelContext.save()
        }

        return didChange
    }

    private static func migrateLegacySnapshotIfNeeded(
        for account: StoredAccount,
        in modelContext: ModelContext,
        snapshotStore: AccountSnapshotStoring,
        syncedRateLimitCredentialStore: SyncedRateLimitCredentialStoring,
        logger: Logger
    ) async -> Bool {
        var didChange = false
        let previousIdentityKey = account.identityKey

        if let syncedContents = account.authFileContents, !syncedContents.isEmpty {
            do {
                let migratedSnapshot = try SharedCodexAuthFile.parse(contents: syncedContents)
                didChange = StoredAccountCloudSyncSupport.update(account, from: migratedSnapshot) || didChange
                try await snapshotStore.saveSnapshot(
                    syncedContents,
                    forIdentityKey: migratedSnapshot.identityKey
                )
                _ = await StoredAccountCloudSyncSupport.exportSyncedRateLimitCredentialIfNeeded(
                    from: syncedContents,
                    expectedIdentityKey: migratedSnapshot.identityKey,
                    in: modelContext,
                    syncedRateLimitCredentialStore: syncedRateLimitCredentialStore,
                    excludingAccountIDsForDelete: [account.id],
                    logger: logger
                )
                account.authFileContents = nil
                didChange = true

                let normalizedPreviousIdentityKey = previousIdentityKey.trimmingCharacters(in: .whitespacesAndNewlines)
                if normalizedPreviousIdentityKey != migratedSnapshot.identityKey,
                   !normalizedPreviousIdentityKey.isEmpty {
                    await StoredAccountCloudSyncSupport.deleteArtifactsIfUnused(
                        identityKey: normalizedPreviousIdentityKey,
                        in: modelContext,
                        snapshotStore: snapshotStore,
                        syncedRateLimitCredentialStore: syncedRateLimitCredentialStore,
                        excludingAccountIDs: [account.id],
                        logger: logger
                    )
                }
            } catch {
                logger.error(
                    "Couldn't migrate synced snapshot for account \(account.id.uuidString, privacy: .public): \(String(describing: error), privacy: .private)"
                )
            }
        }

        let normalizedIdentityKey = account.identityKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedIdentityKey.isEmpty {
            do {
                if try await snapshotStore.migrateLegacySnapshotIfNeeded(
                    fromLegacyAccountID: account.id,
                    toIdentityKey: normalizedIdentityKey
                ) {
                    if let migratedContents = try? await snapshotStore.loadSnapshot(
                        forIdentityKey: normalizedIdentityKey
                    ) {
                        _ = await StoredAccountCloudSyncSupport.exportSyncedRateLimitCredentialIfNeeded(
                            from: migratedContents,
                            expectedIdentityKey: normalizedIdentityKey,
                            in: modelContext,
                            syncedRateLimitCredentialStore: syncedRateLimitCredentialStore,
                            excludingAccountIDsForDelete: [account.id],
                            logger: logger
                        )
                    }
                    didChange = true
                }
            } catch {
                logger.error(
                    "Couldn't migrate legacy keychain snapshot for account \(account.id.uuidString, privacy: .public): \(String(describing: error), privacy: .private)"
                )
            }
        }

        return didChange
    }

    private static func bestAvailableSnapshotContents(
        for account: StoredAccount,
        snapshotStore: AccountSnapshotStoring,
        logger: Logger
    ) async -> String? {
        do {
            return try await snapshotStore.loadSnapshot(forIdentityKey: account.identityKey)
        } catch AccountSnapshotStoreError.missingSnapshot {
            return nil
        } catch {
            logger.error(
                "Couldn't load local snapshot for account \(account.id.uuidString, privacy: .public): \(String(describing: error), privacy: .private)"
            )
            return nil
        }
    }
}
