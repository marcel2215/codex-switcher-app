//
//  RemoteAccountDeletionCleanup.swift
//  Codex Switcher Mac App
//
//  Created by Marcel Kwiatkowski on 2026-04-11.
//

import Foundation
import OSLog
import SwiftData

@MainActor
final class RemoteAccountDeletionCleanup {
    private enum StorageKey {
        static let historyToken = "remote-account-deletion-cleanup.history-token"
    }

    private let modelContainer: ModelContainer
    private let secretStore: AccountSnapshotStoring
    private let syncedRateLimitCredentialStore: SyncedRateLimitCredentialStoring
    private let logger: Logger
    private let userDefaults: UserDefaults

    private var isConsumingHistory = false

    init(
        modelContainer: ModelContainer,
        secretStore: AccountSnapshotStoring,
        syncedRateLimitCredentialStore: SyncedRateLimitCredentialStoring,
        logger: Logger,
        userDefaults: UserDefaults = .standard
    ) {
        self.modelContainer = modelContainer
        self.secretStore = secretStore
        self.syncedRateLimitCredentialStore = syncedRateLimitCredentialStore
        self.logger = logger
        self.userDefaults = userDefaults
    }

    func consumeHistoryIfNeeded() async {
        guard !isConsumingHistory else {
            return
        }

        isConsumingHistory = true
        defer {
            isConsumingHistory = false
        }

        let modelContext = modelContainer.mainContext

        let transactions: [DefaultHistoryTransaction]
        do {
            transactions = try modelContext.fetchHistory(HistoryDescriptor<DefaultHistoryTransaction>())
                .sorted { $0.token < $1.token }
        } catch {
            logger.error("Failed to fetch SwiftData history for remote deletion cleanup: \(String(describing: error), privacy: .private)")
            return
        }

        let lastProcessedToken = loadLastProcessedToken()
        let pendingTransactions = transactions.filter { transaction in
            guard let lastProcessedToken else {
                return true
            }

            return transaction.token > lastProcessedToken
        }

        guard !pendingTransactions.isEmpty else {
            return
        }

        for transaction in pendingTransactions {
            do {
                try await process(transaction, in: modelContext)
                saveLastProcessedToken(transaction.token)
            } catch {
                logger.error("Remote deletion cleanup stopped after transaction \(transaction.transactionIdentifier, privacy: .public): \(String(describing: error), privacy: .private)")
                return
            }
        }
    }

    private func process(
        _ transaction: DefaultHistoryTransaction,
        in modelContext: ModelContext
    ) async throws {
        let deletedIdentityKeys = deletedIdentityKeys(in: transaction)
        guard !deletedIdentityKeys.isEmpty else {
            return
        }

        let remainingIdentityKeys = try currentIdentityKeys(in: modelContext)

        for identityKey in deletedIdentityKeys where !remainingIdentityKeys.contains(identityKey) {
            try await secretStore.deleteSnapshot(forIdentityKey: identityKey)
            try await syncedRateLimitCredentialStore.delete(forIdentityKey: identityKey)
        }
    }

    private func deletedIdentityKeys(in transaction: DefaultHistoryTransaction) -> Set<String> {
        var identityKeys = Set<String>()

        for change in transaction.changes {
            guard case let .delete(deleteChange) = change,
                  let storedAccountDelete = deleteChange as? DefaultHistoryDelete<StoredAccount>,
                  let tombstoneIdentityKey = storedAccountDelete.tombstone[\.identityKey] as? String else {
                continue
            }

            let normalizedIdentityKey = tombstoneIdentityKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedIdentityKey.isEmpty else {
                continue
            }

            identityKeys.insert(normalizedIdentityKey)
        }

        return identityKeys
    }

    private func currentIdentityKeys(in modelContext: ModelContext) throws -> Set<String> {
        let descriptor = FetchDescriptor<StoredAccount>()
        return Set(
            try modelContext.fetch(descriptor)
                .map(\.identityKey)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    private func loadLastProcessedToken() -> DefaultHistoryToken? {
        guard let data = userDefaults.data(forKey: StorageKey.historyToken) else {
            return nil
        }

        return try? JSONDecoder().decode(DefaultHistoryToken.self, from: data)
    }

    private func saveLastProcessedToken(_ token: DefaultHistoryToken) {
        guard let encodedToken = try? JSONEncoder().encode(token) else {
            logger.error("Failed to encode SwiftData history token for remote deletion cleanup.")
            return
        }

        userDefaults.set(encodedToken, forKey: StorageKey.historyToken)
    }
}
