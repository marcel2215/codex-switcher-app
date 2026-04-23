//
//  StoredAccountMutations.swift
//  Codex Switcher
//
//  Created by Marcel Kwiatkowski on 2026-04-12.
//

import Foundation
import SwiftData

enum StoredAccountMutations {
    @MainActor
    static func rename(
        _ account: StoredAccount,
        to proposedName: String,
        in modelContext: ModelContext
    ) throws {
        guard !account.isDeleted else {
            return
        }

        let trimmedName = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLegacyFields = account.normalizeLegacyLocalOnlyFields()
        guard account.name != trimmedName || normalizedLegacyFields else {
            return
        }

        account.name = trimmedName
        try modelContext.save()
    }

    @MainActor
    static func setIcon(
        _ icon: AccountIconOption,
        for account: StoredAccount,
        in modelContext: ModelContext
    ) throws {
        guard !account.isDeleted else {
            return
        }

        let resolvedSystemName = AccountIconOption.resolve(from: icon.systemName).systemName
        let normalizedLegacyFields = account.normalizeLegacyLocalOnlyFields()
        guard account.iconSystemName != resolvedSystemName || normalizedLegacyFields else {
            return
        }

        account.iconSystemName = resolvedSystemName
        try modelContext.save()
    }

    @MainActor
    static func setPinned(
        _ isPinned: Bool,
        for account: StoredAccount,
        in modelContext: ModelContext
    ) throws {
        guard !account.isDeleted else {
            return
        }

        let normalizedLegacyFields = account.normalizeLegacyLocalOnlyFields()
        guard account.isPinned != isPinned || normalizedLegacyFields else {
            return
        }

        account.isPinned = isPinned
        try modelContext.save()
    }

    @MainActor
    static func remove(
        _ account: StoredAccount,
        in modelContext: ModelContext,
        snapshotStore: AccountSnapshotStoring = SharedKeychainSnapshotStore(),
        syncedRateLimitCredentialStore: SyncedRateLimitCredentialStoring = SyncedRateLimitCredentialStore()
    ) async throws {
        guard !account.isDeleted else {
            return
        }

        let deletedIdentityKey = account.identityKey.trimmingCharacters(in: .whitespacesAndNewlines)
        modelContext.delete(account)
        try modelContext.save()

        guard !deletedIdentityKey.isEmpty else {
            return
        }

        await StoredAccountCloudSyncSupport.deleteArtifactsIfUnused(
            identityKey: deletedIdentityKey,
            in: modelContext,
            snapshotStore: snapshotStore,
            syncedRateLimitCredentialStore: syncedRateLimitCredentialStore
        )
    }

    @MainActor
    static func removeAll(
        _ accounts: [StoredAccount],
        in modelContext: ModelContext,
        snapshotStore: AccountSnapshotStoring = SharedKeychainSnapshotStore(),
        syncedRateLimitCredentialStore: SyncedRateLimitCredentialStoring = SyncedRateLimitCredentialStore()
    ) async throws {
        let accountsToRemove = accounts.filter { !$0.isDeleted }
        guard !accountsToRemove.isEmpty else {
            return
        }

        let deletedIdentityKeys = Set(
            accountsToRemove
                .map(\.identityKey)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )

        for account in accountsToRemove {
            modelContext.delete(account)
        }

        try modelContext.save()

        for identityKey in deletedIdentityKeys {
            await StoredAccountCloudSyncSupport.deleteArtifactsIfUnused(
                identityKey: identityKey,
                in: modelContext,
                snapshotStore: snapshotStore,
                syncedRateLimitCredentialStore: syncedRateLimitCredentialStore
            )
        }
    }
}
