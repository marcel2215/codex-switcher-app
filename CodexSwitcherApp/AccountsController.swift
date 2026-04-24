//
//  AccountsController.swift
//  Codex Switcher
//
//  Created by Marcel Kwiatkowski on 2026-04-11.
//

import Foundation
import Observation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class IOSAccountsController {
    private let snapshotStore: AccountSnapshotStoring
    private let archiveExporter: CodexAccountArchiveFileExporter
    private let syncedRateLimitCredentialStore: SyncedRateLimitCredentialStoring
    private let snapshotAvailabilityStore: LocalAccountSnapshotAvailabilityStore

    var searchText = ""
    var archiveAvailabilityRefreshToken = 0
    var sortCriterion: AccountSortCriterion = .dateAdded {
        didSet {
            let normalizedDirection = AccountsPresentationLogic.normalizedSortDirection(
                for: sortCriterion,
                requestedDirection: sortDirection
            )

            if sortDirection != normalizedDirection {
                sortDirection = normalizedDirection
            }
        }
    }
    var sortDirection: SortDirection = .ascending {
        didSet {
            let normalizedDirection = AccountsPresentationLogic.normalizedSortDirection(
                for: sortCriterion,
                requestedDirection: sortDirection
            )

            if sortDirection != normalizedDirection {
                sortDirection = normalizedDirection
            }
        }
    }
    var presentedError: PresentedError?

    init(
        snapshotStore: AccountSnapshotStoring = SharedKeychainSnapshotStore(),
        archiveExporter: CodexAccountArchiveFileExporter = CodexAccountArchiveFileExporter(),
        syncedRateLimitCredentialStore: SyncedRateLimitCredentialStoring = SyncedRateLimitCredentialStore(),
        snapshotAvailabilityStore: LocalAccountSnapshotAvailabilityStore = LocalAccountSnapshotAvailabilityStore()
    ) {
        self.snapshotStore = snapshotStore
        self.archiveExporter = archiveExporter
        self.syncedRateLimitCredentialStore = syncedRateLimitCredentialStore
        self.snapshotAvailabilityStore = snapshotAvailabilityStore
    }

    var canEditCustomOrder: Bool {
        AccountsPresentationLogic.canEditCustomOrder(
            searchText: searchText,
            sortCriterion: sortCriterion,
            sortDirection: sortDirection
        )
    }

    func restoreSortPreferences(
        sortCriterionRawValue: String,
        sortDirectionRawValue: String
    ) {
        let resolvedCriterion = AccountSortCriterion(rawValue: sortCriterionRawValue) ?? .dateAdded
        let resolvedDirection = AccountsPresentationLogic.normalizedSortDirection(
            for: resolvedCriterion,
            requestedDirection: SortDirection(rawValue: sortDirectionRawValue) ?? .ascending
        )

        if sortCriterion != resolvedCriterion {
            sortCriterion = resolvedCriterion
        }

        if sortDirection != resolvedDirection {
            sortDirection = resolvedDirection
        }
    }

    func displayedAccounts(from accounts: [StoredAccount]) -> [StoredAccount] {
        AccountsPresentationLogic.displayedAccounts(
            from: accounts,
            searchText: searchText,
            sortCriterion: sortCriterion,
            sortDirection: sortDirection
        )
    }

    func archiveTransferItem(for account: StoredAccount) -> CodexAccountArchiveTransferItem {
        CodexAccountArchiveTransferItem(
            id: account.id,
            request: CodexAccountArchiveExportRequest(
                account: account,
                hasLocalSnapshot: snapshotAvailabilityStore.containsSnapshot(
                    forIdentityKey: account.identityKey
                )
            ),
            exporter: archiveExporter
        )
    }

    func canExportArchive(for account: StoredAccount) async -> Bool {
        await archiveTransferItem(for: account).canExport()
    }

    func prepareArchiveFile(for account: StoredAccount) async throws -> PreparedCodexAccountArchiveFile {
        let transferItem = archiveTransferItem(for: account)
        let fileURL = try await archiveExporter.exportFile(for: transferItem.request)
        return PreparedCodexAccountArchiveFile(
            fileURL: fileURL,
            suggestedFilename: transferItem.exportedArchiveFilename
        )
    }

    /// Home Screen quick actions should reflect the same ordering rules as the
    /// in-app list, but they intentionally ignore transient search filtering so
    /// SpringBoard suggestions remain stable outside the current UI session.
    func homeScreenQuickActionAccounts(
        from accounts: [StoredAccount],
        limit: Int
    ) -> [IOSHomeScreenQuickActionAccountItem] {
        guard limit > 0 else {
            return []
        }

        return Array(
            AccountsPresentationLogic.sortedAccounts(
                from: accounts,
                sortCriterion: sortCriterion,
                sortDirection: sortDirection
            )
            .prefix(limit)
        )
        .map { account in
            return IOSHomeScreenQuickActionAccountItem(
                id: account.id,
                title: AccountsPresentationLogic.displayName(for: account),
                subtitle: nil,
                iconSystemName: AccountIconOption.resolve(from: account.iconSystemName).systemName
            )
        }
    }

    func commitRename(for account: StoredAccount, proposedName: String, in modelContext: ModelContext) {
        guard !account.isDeleted else {
            return
        }

        do {
            try StoredAccountMutations.rename(account, to: proposedName, in: modelContext)
        } catch {
            presentedError = PresentedError(
                title: "Couldn't Rename Account",
                message: error.localizedDescription
            )
        }
    }

    func setIcon(_ icon: AccountIconOption, for account: StoredAccount, in modelContext: ModelContext) {
        guard !account.isDeleted else {
            return
        }

        let resolvedSystemName = AccountIconOption.resolve(from: icon.systemName).systemName
        guard account.iconSystemName != resolvedSystemName else {
            return
        }

        do {
            try StoredAccountMutations.setIcon(icon, for: account, in: modelContext)
        } catch {
            presentedError = PresentedError(
                title: "Couldn't Change Icon",
                message: error.localizedDescription
            )
        }
    }

    func setPinned(_ isPinned: Bool, for account: StoredAccount, in modelContext: ModelContext) {
        guard !account.isDeleted else {
            return
        }

        do {
            try StoredAccountMutations.setPinned(isPinned, for: account, in: modelContext)
        } catch {
            presentedError = PresentedError(
                title: isPinned ? "Couldn't Pin Account" : "Couldn't Unpin Account",
                message: error.localizedDescription
            )
        }
    }

    func remove(_ account: StoredAccount, in modelContext: ModelContext) async {
        guard !account.isDeleted else {
            return
        }

        do {
            try await StoredAccountMutations.remove(
                account,
                in: modelContext,
                snapshotStore: snapshotStore,
                syncedRateLimitCredentialStore: syncedRateLimitCredentialStore
            )
        } catch {
            presentedError = PresentedError(
                title: "Couldn't Remove Account",
                message: error.localizedDescription
            )
        }
    }

    func removeAccounts(
        withIDs accountIDs: Set<UUID>,
        from accounts: [StoredAccount],
        in modelContext: ModelContext
    ) async {
        guard !accountIDs.isEmpty else {
            return
        }

        let accountsToRemove = accounts.filter { accountIDs.contains($0.id) && !$0.isDeleted }
        guard !accountsToRemove.isEmpty else {
            return
        }

        do {
            try await StoredAccountMutations.removeAll(
                accountsToRemove,
                in: modelContext,
                snapshotStore: snapshotStore,
                syncedRateLimitCredentialStore: syncedRateLimitCredentialStore
            )
        } catch {
            presentedError = PresentedError(
                title: "Couldn't Remove Accounts",
                message: error.localizedDescription
            )
        }
    }

    func move(
        from source: IndexSet,
        to destination: Int,
        visibleAccounts: [StoredAccount],
        in modelContext: ModelContext
    ) {
        guard canEditCustomOrder else {
            return
        }

        var reorderedAccounts = visibleAccounts
        reorderedAccounts.move(fromOffsets: source, toOffset: destination)

        persistCustomOrder(for: reorderedAccounts, in: modelContext)
    }

    @discardableResult
    func importAccountArchives(
        from urls: [URL],
        in modelContext: ModelContext
    ) async -> [UUID] {
        let accountArchiveURLs = urls.filter(Self.isAccountArchiveURL)
        guard !accountArchiveURLs.isEmpty else {
            presentedError = PresentedError(
                title: "Couldn't Import Account",
                message: "No supported .cxa files were provided."
            )
            return []
        }

        do {
            var allAccounts = try modelContext.fetch(FetchDescriptor<StoredAccount>())
            var importedAccountIDs: [UUID] = []
            var failureMessages: [String] = []

            for url in accountArchiveURLs {
                do {
                    let archive = try Self.loadAccountArchive(from: url)
                    for (accountIndex, archivedAccount) in archive.accounts.enumerated() {
                        do {
                            let snapshot = try Self.parseImportedSnapshot(
                                from: archivedAccount.snapshotContents
                            )

                            if let archivedIdentityKey = archivedAccount.identityKey?
                                .trimmingCharacters(in: .whitespacesAndNewlines),
                               !archivedIdentityKey.isEmpty,
                               archivedIdentityKey != snapshot.identityKey {
                                throw IOSAccountImportError.identityMismatch
                            }

                            if let existingAccount = allAccounts.first(where: {
                                $0.identityKey == snapshot.identityKey
                            }) {
                                _ = try await storeImportedSnapshot(
                                    archivedAccount.snapshotContents,
                                    snapshot: snapshot,
                                    on: existingAccount,
                                    in: modelContext
                                )
                                _ = Self.applyImportedArchiveMetadata(
                                    archivedAccount,
                                    to: existingAccount
                                )

                                // Treat a byte-for-byte re-import as a successful
                                // selection/import operation rather than surfacing a
                                // false failure just because nothing changed locally.
                                if !importedAccountIDs.contains(existingAccount.id) {
                                    importedAccountIDs.append(existingAccount.id)
                                }
                                continue
                            }

                            guard allAccounts.count < 1_000 else {
                                throw IOSAccountImportError.accountLimitReached
                            }

                            let nextCustomOrder = (allAccounts.map(\.customOrder).max() ?? -1) + 1
                            let account = StoredAccount(
                                identityKey: snapshot.identityKey,
                                name: archivedAccount.preferredStoredName
                                    ?? Self.defaultName(for: snapshot, existingAccounts: allAccounts),
                                customOrder: nextCustomOrder,
                                authModeRaw: snapshot.authMode.rawValue,
                                emailHint: snapshot.email,
                                accountIdentifier: snapshot.accountIdentifier,
                                iconSystemName: archivedAccount.resolvedIconSystemName
                            )

                            _ = try await storeImportedSnapshot(
                                archivedAccount.snapshotContents,
                                snapshot: snapshot,
                                on: account,
                                in: modelContext
                            )
                            modelContext.insert(account)
                            allAccounts.append(account)
                            importedAccountIDs.append(account.id)
                        } catch {
                            let accountLabel = archivedAccount.preferredStoredName
                                ?? archivedAccount.identityKey
                                ?? "Account \(accountIndex + 1)"
                            failureMessages.append(
                                "\(url.lastPathComponent) • \(accountLabel): \(error.localizedDescription)"
                            )
                        }
                    }
                } catch {
                    failureMessages.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }

            guard !importedAccountIDs.isEmpty else {
                presentedError = PresentedError(
                    title: "Couldn't Import Account",
                    message: failureMessages.isEmpty
                        ? "Codex Switcher couldn't import that .cxa file."
                        : failureMessages.joined(separator: "\n")
                )
                return []
            }

            try modelContext.save()
            archiveAvailabilityRefreshToken &+= 1

            if !failureMessages.isEmpty {
                presentedError = PresentedError(
                    title: "Imported with Issues",
                    message: failureMessages.joined(separator: "\n")
                )
            }

            return importedAccountIDs
        } catch {
            presentedError = PresentedError(
                title: "Couldn't Import Account",
                message: error.localizedDescription
            )
            return []
        }
    }

    private func persistCustomOrder(
        for reorderedAccounts: [StoredAccount],
        in modelContext: ModelContext
    ) {
        do {
            let persistedAccounts = AccountsPresentationLogic.customOrderPersistenceSequence(
                for: reorderedAccounts
            )

            for (index, account) in persistedAccounts.enumerated() {
                account.customOrder = Double(index)
                _ = account.normalizeLegacyLocalOnlyFields()
            }

            try modelContext.save()
        } catch {
            presentedError = PresentedError(
                title: "Couldn't Reorder Accounts",
                message: error.localizedDescription
            )
        }
    }

    private func storeImportedSnapshot(
        _ snapshotContents: String,
        snapshot: SharedCodexAuthSnapshot,
        on account: StoredAccount,
        in modelContext: ModelContext
    ) async throws -> Bool {
        let previousIdentityKey = account.identityKey
        var didChange = StoredAccountCloudSyncSupport.update(account, from: snapshot)

        if account.authFileContents != nil {
            account.authFileContents = nil
            didChange = true
        }

        var shouldSaveSnapshot = true
        if previousIdentityKey == snapshot.identityKey {
            do {
                let existingSnapshotContents = try await snapshotStore.loadSnapshot(
                    forIdentityKey: snapshot.identityKey
                )
                shouldSaveSnapshot = existingSnapshotContents != snapshotContents
            } catch AccountSnapshotStoreError.missingSnapshot {
                shouldSaveSnapshot = true
            }
        }

        if shouldSaveSnapshot {
            try await snapshotStore.saveSnapshot(snapshotContents, forIdentityKey: snapshot.identityKey)
        }

        let didExportSyncedCredential =
            await StoredAccountCloudSyncSupport.exportSyncedRateLimitCredentialIfNeeded(
            from: snapshotContents,
            expectedIdentityKey: snapshot.identityKey,
            in: modelContext,
            syncedRateLimitCredentialStore: syncedRateLimitCredentialStore,
            excludingAccountIDsForDelete: [account.id],
            forceRewrite: StoredAccountCloudSyncSupport.shouldForceRewriteSyncedRateLimitCredential(
                for: snapshot.identityKey
            )
        )
        if didExportSyncedCredential || snapshot.authMode == .apiKey {
            StoredAccountCloudSyncSupport.markSyncedRateLimitCredentialAccessibilityMigrated(
                for: snapshot.identityKey
            )
        }

        if previousIdentityKey != snapshot.identityKey,
           previousIdentityKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            await StoredAccountCloudSyncSupport.deleteArtifactsIfUnused(
                identityKey: previousIdentityKey,
                in: modelContext,
                snapshotStore: snapshotStore,
                syncedRateLimitCredentialStore: syncedRateLimitCredentialStore,
                excludingAccountIDs: [account.id]
            )
        }

        return didChange
    }

    private static func parseImportedSnapshot(from snapshotContents: String) throws -> SharedCodexAuthSnapshot {
        try SharedCodexAuthFile.parse(contents: snapshotContents)
    }

    private static func applyImportedArchiveMetadata(
        _ archive: CodexAccountArchive.Account,
        to account: StoredAccount
    ) -> Bool {
        var didChange = false

        if let importedName = archive.preferredStoredName,
           (account.name.isEmpty || isGeneratedAccountName(account.name)),
           account.name != importedName {
            account.name = importedName
            didChange = true
        }

        let importedIconSystemName = archive.resolvedIconSystemName
        if account.iconSystemName == AccountIconOption.defaultOption.systemName,
           importedIconSystemName != AccountIconOption.defaultOption.systemName {
            account.iconSystemName = importedIconSystemName
            didChange = true
        }

        return didChange
    }

    private static func defaultName(
        for snapshot: SharedCodexAuthSnapshot,
        existingAccounts: [StoredAccount]
    ) -> String {
        if let preferredEmail = snapshot.email?.trimmingCharacters(in: .whitespacesAndNewlines), !preferredEmail.isEmpty {
            return preferredEmail
        }

        return nextGeneratedAccountName(existingAccounts: existingAccounts)
    }

    private static func nextGeneratedAccountName(existingAccounts: [StoredAccount]) -> String {
        let usedIndices = Set(existingAccounts.compactMap { generatedAccountIndex(from: $0.name) })

        var candidateIndex = 1
        while usedIndices.contains(candidateIndex) {
            candidateIndex += 1
        }

        return "Account \(candidateIndex)"
    }

    private static func generatedAccountIndex(from name: String) -> Int? {
        guard name.hasPrefix("Account ") else {
            return nil
        }

        return Int(name.dropFirst("Account ".count))
    }

    private static func isGeneratedAccountName(_ name: String) -> Bool {
        generatedAccountIndex(from: name) != nil
    }

    private static func isAccountArchiveURL(_ url: URL) -> Bool {
        if let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
           contentType.isCodexAccountArchiveType {
            return true
        }

        return url.pathExtension.localizedCaseInsensitiveCompare("cxa") == .orderedSame
    }

    private static func loadAccountArchive(from url: URL) throws -> CodexAccountArchive {
        try withSecurityScopedAccess(to: url) {
            let archiveData = try Data(contentsOf: url, options: .mappedIfSafe)
            return try CodexAccountArchive.decode(from: archiveData)
        }
    }

    private static func withSecurityScopedAccess<T>(
        to url: URL,
        operation: () throws -> T
    ) throws -> T {
        let startedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if startedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return try operation()
    }
}

private enum IOSAccountImportError: LocalizedError {
    case identityMismatch
    case accountLimitReached

    var errorDescription: String? {
        switch self {
        case .identityMismatch:
            "That .cxa file doesn't match the account snapshot it contains."
        case .accountLimitReached:
            "Codex Switcher supports up to 1000 saved accounts."
        }
    }
}
