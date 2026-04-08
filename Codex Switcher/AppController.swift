//
//  AppController.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-08.
//

import Foundation
import Observation
import OSLog
import SwiftData
import SwiftUI

struct UserFacingAlert: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
}

@Observable
@MainActor
final class AppController {
    var selection: Set<UUID> = []
    var searchText = ""
    var sortCriterion: AccountSortCriterion = .dateAdded
    var sortDirection: SortDirection = .ascending
    var renameTargetID: UUID?
    var presentedAlert: UserFacingAlert?
    var isShowingLocationPicker = false
    private(set) var activeIdentityKey: String?
    private(set) var authAccessState: AuthAccessState = .unlinked
    private(set) var isSwitching = false

    @ObservationIgnored private let authFileManager: AuthFileManaging
    @ObservationIgnored private let secretStore: AccountSecretStoring
    @ObservationIgnored private let notificationManager: AccountSwitchNotifying
    @ObservationIgnored private let logger: Logger
    @ObservationIgnored private let startupAlert: UserFacingAlert?

    @ObservationIgnored private var modelContext: ModelContext?
    @ObservationIgnored private var hasConfiguredInitialState = false
    @ObservationIgnored private var hasStartedMonitoring = false
    @ObservationIgnored private var pendingLocationAction: PendingLocationAction?
    @ObservationIgnored private var initializationTask: Task<Void, Never>?
    @ObservationIgnored private var switchTask: Task<Void, Never>?
    @ObservationIgnored private var activeSwitchOperationID: UUID?

    init(
        authFileManager: AuthFileManaging,
        secretStore: AccountSecretStoring,
        notificationManager: AccountSwitchNotifying,
        startupAlert: UserFacingAlert? = nil,
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "CodexSwitcher"
    ) {
        self.authFileManager = authFileManager
        self.secretStore = secretStore
        self.notificationManager = notificationManager
        self.startupAlert = startupAlert
        self.logger = Logger(subsystem: bundleIdentifier, category: "AppController")
    }

    deinit {
        initializationTask?.cancel()
        switchTask?.cancel()
    }

    func configure(modelContext: ModelContext, undoManager: UndoManager?) {
        self.modelContext = modelContext
        modelContext.undoManager = undoManager

        guard !hasConfiguredInitialState else {
            return
        }

        hasConfiguredInitialState = true

        if let startupAlert {
            presentedAlert = startupAlert
        }

        startMonitoringIfNeeded()

        let initializationTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            await self.reconcileStoredSnapshotsIfNeeded()
            await self.refreshAuthState(showUnexpectedErrors: false)
            self.reconcileDisplayOnlyFieldsIfNeeded()
            self.initializationTask = nil
        }
        self.initializationTask = initializationTask
    }

    var canEditCustomOrder: Bool {
        sortCriterion == .custom && searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var selectedAccountID: UUID? {
        guard selection.count == 1 else {
            return nil
        }

        return selection.first
    }

    var selectedAccountIconOption: AccountIconOption? {
        guard
            let selectedAccountID,
            let account = try? account(withID: selectedAccountID)
        else {
            return nil
        }

        return AccountIconOption.resolve(from: account.iconSystemName)
    }

    var shouldShowAuthStatusBanner: Bool {
        authAccessState.showsInlineStatus
    }

    var linkedFolderPath: String? {
        authAccessState.linkedFolderURL?.path
    }

    var settingsLinkButtonTitle: String {
        "Select"
    }

    var linkButtonTitle: String {
        switch authAccessState {
        case .unlinked:
            "Link Codex Folder"
        case .locationUnavailable, .accessDenied, .corruptAuthFile, .unsupportedCredentialStore:
            "Relink Codex Folder"
        case .ready, .missingAuthFile:
            "Link Codex Folder"
        }
    }

    func displayedAccounts(from accounts: [StoredAccount]) -> [StoredAccount] {
        let filteredAccounts: [StoredAccount]
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedSearch.isEmpty {
            filteredAccounts = accounts
        } else {
            let lowercasedSearch = trimmedSearch.lowercased()
            filteredAccounts = accounts.filter { account in
                account.name.lowercased().contains(lowercasedSearch)
                    || (account.emailHint?.lowercased().contains(lowercasedSearch) ?? false)
                    || (account.accountIdentifier?.lowercased().contains(lowercasedSearch) ?? false)
            }
        }

        return filteredAccounts.sorted(by: sortComparator)
    }

    func beginLinkingCodexLocation() {
        pendingLocationAction = nil
        isShowingLocationPicker = true
    }

    func handleLocationImport(_ result: Result<[URL], any Error>) {
        Task { [weak self] in
            guard let self else {
                return
            }

            await self.finishLocationImport(result)
        }
    }

    func refresh() {
        Task { [weak self] in
            guard let self else {
                return
            }

            await self.refreshAuthState(showUnexpectedErrors: true)
        }
    }

    func captureCurrentAccount() {
        Task { [weak self] in
            guard let self else {
                return
            }

            await self.captureCurrentAccountNow()
        }
    }

    func login(accountID: UUID) {
        let operationID = UUID()
        activeSwitchOperationID = operationID
        switchTask?.cancel()
        switchTask = Task { [weak self] in
            guard let self else {
                return
            }

            await self.switchToAccountNow(id: accountID, operationID: operationID)
        }
    }

    func switchSelectedAccount() {
        guard selection.count == 1, let accountID = selection.first else {
            return
        }

        login(accountID: accountID)
    }

    func beginRenamingSelectedAccount() {
        guard selection.count == 1, let accountID = selection.first else {
            return
        }

        beginRenaming(accountID: accountID)
    }

    func beginRenaming(accountID: UUID) {
        selection = [accountID]
        renameTargetID = accountID
    }

    func cancelRename(for accountID: UUID) {
        guard renameTargetID == accountID else {
            return
        }

        renameTargetID = nil
    }

    func commitRename(for accountID: UUID, proposedName: String) {
        do {
            guard let account = try account(withID: accountID) else {
                throw ControllerError.accountNotFound
            }

            let trimmedName = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else {
                renameTargetID = nil
                return
            }

            account.name = trimmedName
            try requireModelContext().save()
            renameTargetID = nil
        } catch {
            present(error, title: "Couldn't Rename Account")
        }
    }

    func setIcon(_ icon: AccountIconOption, for accountID: UUID) {
        do {
            guard let account = try account(withID: accountID) else {
                throw ControllerError.accountNotFound
            }

            let resolvedSystemName = AccountIconOption.resolve(from: icon.systemName).systemName
            guard account.iconSystemName != resolvedSystemName else {
                return
            }

            account.iconSystemName = resolvedSystemName
            try requireModelContext().save()
        } catch {
            present(error, title: "Couldn't Change Icon")
        }
    }

    func setSelectedAccountIcon(_ icon: AccountIconOption) {
        guard let selectedAccountID else {
            return
        }

        setIcon(icon, for: selectedAccountID)
    }

    func removeSelectedAccounts() {
        Task { [weak self] in
            guard let self else {
                return
            }

            await self.removeAccountsNow(withIDs: self.selection)
        }
    }

    func removeAccounts(withIDs ids: Set<UUID>) {
        Task { [weak self] in
            guard let self else {
                return
            }

            await self.removeAccountsNow(withIDs: ids)
        }
    }

    func reorderDraggedAccounts(_ items: [String], to destinationIndex: Int, visibleAccounts: [StoredAccount]) {
        guard
            canEditCustomOrder,
            let movingID = items.first.flatMap(UUID.init(uuidString:)),
            let sourceIndex = visibleAccounts.firstIndex(where: { $0.id == movingID })
        else {
            return
        }

        let boundedDropIndex = min(max(destinationIndex, 0), visibleAccounts.count)
        var finalIndex = boundedDropIndex

        if sourceIndex < boundedDropIndex {
            finalIndex -= 1
        }

        finalIndex = min(max(finalIndex, 0), max(visibleAccounts.count - 1, 0))
        moveAccount(withID: movingID, to: finalIndex, visibleAccounts: visibleAccounts)
    }

    func moveSelection(direction: MoveCommandDirection, visibleAccounts: [StoredAccount]) {
        guard
            canEditCustomOrder,
            selection.count == 1,
            let selectedID = selection.first,
            let currentIndex = visibleAccounts.firstIndex(where: { $0.id == selectedID })
        else {
            return
        }

        let destinationIndex: Int
        switch direction {
        case .up:
            destinationIndex = max(currentIndex - 1, 0)
        case .down:
            destinationIndex = min(currentIndex + 1, visibleAccounts.count - 1)
        default:
            return
        }

        moveAccount(withID: selectedID, to: destinationIndex, visibleAccounts: visibleAccounts)
    }

    func captureCurrentAccountNow() async {
        await waitForInitializationIfNeeded()

        do {
            let readResult = try await authFileManager.readAuthFile()
            let snapshot = try await parseSnapshot(from: readResult.contents)
            let modelContext = try requireModelContext()
            let accounts = try fetchAccounts()

            if let existingAccount = accounts.first(where: { $0.identityKey == snapshot.identityKey }) {
                _ = await storeSnapshot(snapshot, on: existingAccount)
                selection = [existingAccount.id]
            } else {
                guard accounts.count < 1_000 else {
                    throw ControllerError.accountLimitReached
                }

                let nextCustomOrder = (accounts.map(\.customOrder).max() ?? -1) + 1
                let account = StoredAccount(
                    identityKey: snapshot.identityKey,
                    name: "Account \(accounts.count + 1)",
                    customOrder: nextCustomOrder,
                    authFileContents: snapshot.rawContents,
                    authModeRaw: snapshot.authMode.rawValue,
                    emailHint: snapshot.email,
                    accountIdentifier: snapshot.accountIdentifier
                )

                modelContext.insert(account)
                await cacheSecretLocallyIfPossible(snapshot.rawContents, for: account.id)

                selection = [account.id]
            }

            try modelContext.save()
            searchText = ""
            activeIdentityKey = snapshot.identityKey
            authAccessState = .ready(linkedFolder: readResult.url.deletingLastPathComponent())
        } catch {
            await handleExpectedAuthOperationError(
                error,
                title: "Couldn't Save Account",
                retryAction: .captureCurrentAccount
            )
        }
    }

    func switchToAccountNow(id: UUID, operationID: UUID? = nil) async {
        await waitForInitializationIfNeeded()

        let resolvedOperationID = operationID ?? UUID()
        activeSwitchOperationID = resolvedOperationID
        isSwitching = true
        defer {
            if activeSwitchOperationID == resolvedOperationID {
                isSwitching = false
            }
        }

        do {
            let modelContext = try requireModelContext()
            let targetAccount = try requireAccount(withID: id)
            let desiredAuthContents = try await loadStoredSnapshot(for: targetAccount)

            await preserveCurrentLiveSnapshotIfKnown()
            try Task.checkCancellation()

            try await authFileManager.writeAuthFile(desiredAuthContents)

            let verifiedRead = try await authFileManager.readAuthFile()
            let verifiedSnapshot = try await parseSnapshot(from: verifiedRead.contents)
            guard verifiedSnapshot.identityKey == targetAccount.identityKey else {
                throw AuthFileAccessError.verificationFailed(verifiedRead.url)
            }

            activeIdentityKey = verifiedSnapshot.identityKey
            authAccessState = .ready(linkedFolder: verifiedRead.url.deletingLastPathComponent())
            selection = [targetAccount.id]
            renameTargetID = nil
            targetAccount.lastLoginAt = .now

            do {
                try modelContext.save()
            } catch {
                present(
                    UserFacingAlert(
                        title: "Account Switched",
                        message: "The Codex account changed successfully, but the local metadata update failed: \(error.localizedDescription)"
                    )
                )
            }

            await notificationManager.postSwitchNotification(for: targetAccount.name)
        } catch is CancellationError {
            return
        } catch {
            await handleExpectedAuthOperationError(
                error,
                title: "Couldn't Switch Account",
                retryAction: .switchAccount(id)
            )
        }
    }

    func removeAccountsNow(withIDs ids: Set<UUID>) async {
        await waitForInitializationIfNeeded()

        guard !ids.isEmpty else {
            return
        }

        do {
            let modelContext = try requireModelContext()
            let accountsToDelete = try fetchAccounts().filter { ids.contains($0.id) }

            for account in accountsToDelete {
                try? await secretStore.deleteSecret(for: account.id)
                modelContext.delete(account)
            }

            selection.subtract(ids)
            if let renameTargetID, ids.contains(renameTargetID) {
                self.renameTargetID = nil
            }

            try modelContext.save()
        } catch {
            present(error, title: "Couldn't Remove Account")
        }
    }

    func refreshAuthStateForTesting() async {
        await waitForInitializationIfNeeded()
        await refreshAuthState(showUnexpectedErrors: false)
    }

    func handleLocationImportForTesting(_ result: Result<[URL], any Error>) async {
        await waitForInitializationIfNeeded()
        await finishLocationImport(result)
    }

    private func parseSnapshot(from contents: String) async throws -> CodexAuthSnapshot {
        // Decode auth payloads away from the main actor so UI updates are not
        // blocked by file parsing or future auth.json schema growth.
        try await Task.detached(priority: .userInitiated) {
            try CodexAuthFile.parse(contents: contents)
        }.value
    }

    private func waitForInitializationIfNeeded() async {
        let initializationTask = initializationTask
        await initializationTask?.value
    }

    private func startMonitoringIfNeeded() {
        guard !hasStartedMonitoring else {
            return
        }

        hasStartedMonitoring = true

        Task { [weak self] in
            guard let self else {
                return
            }

            await self.authFileManager.startMonitoring { [weak self] in
                guard let self else {
                    return
                }

                Task { @MainActor [weak self] in
                    guard let self else {
                        return
                    }

                    await self.refreshAuthState(showUnexpectedErrors: false)
                }
            }
        }
    }

    private func finishLocationImport(_ result: Result<[URL], any Error>) async {
        switch result {
        case let .success(urls):
            guard let selectedURL = urls.first else {
                pendingLocationAction = nil
                return
            }

            do {
                _ = try await authFileManager.linkLocation(selectedURL)
                let pendingAction = pendingLocationAction
                pendingLocationAction = nil
                await refreshAuthState(showUnexpectedErrors: false)
                await retryPendingLocationActionIfNeeded(pendingAction)
            } catch {
                pendingLocationAction = nil
                present(error, title: "Couldn't Link Codex Folder")
            }

        case let .failure(error):
            pendingLocationAction = nil
            guard !Self.shouldSilentlyDismiss(error) else {
                return
            }

            present(error, title: "Couldn't Link Codex Folder")
        }
    }

    private func retryPendingLocationActionIfNeeded(_ pendingLocationAction: PendingLocationAction?) async {
        guard let pendingLocationAction else {
            return
        }

        switch pendingLocationAction {
        case .captureCurrentAccount:
            await captureCurrentAccountNow()
        case let .switchAccount(accountID):
            await switchToAccountNow(id: accountID)
        case .refresh:
            await refreshAuthState(showUnexpectedErrors: true)
        }
    }

    private func reconcileStoredSnapshotsIfNeeded() async {
        guard let modelContext else {
            return
        }

        do {
            let accounts = try fetchAccounts()
            var didChange = false

            for account in accounts {
                guard let storedContents = await bestAvailableSnapshotContents(for: account) else {
                    continue
                }

                do {
                    let snapshot = try await parseSnapshot(from: storedContents)
                    didChange = await storeSnapshot(snapshot, on: account) || didChange
                } catch {
                    logger.error("Stored snapshot reconciliation failed for account \(account.id.uuidString, privacy: .public): \(String(describing: error), privacy: .private)")
                }
            }

            didChange = await reconcileDuplicateAccountsIfNeeded() || didChange

            if didChange {
                try modelContext.save()
            }
        } catch {
            present(error, title: "Couldn't Upgrade Saved Accounts")
        }
    }

    private func reconcileDisplayOnlyFieldsIfNeeded() {
        guard let modelContext else {
            return
        }

        do {
            var didChange = false

            for account in try fetchAccounts() where account.iconSystemName.isEmpty {
                account.iconSystemName = AccountIconOption.defaultOption.systemName
                didChange = true
            }

            if didChange {
                try modelContext.save()
            }
        } catch {
            present(error, title: "Couldn't Refresh Saved Accounts")
        }
    }

    private func refreshAuthState(showUnexpectedErrors: Bool) async {
        guard let linkedLocation = await authFileManager.linkedLocation() else {
            activeIdentityKey = nil
            authAccessState = .unlinked
            return
        }

        if !linkedLocation.credentialStoreHint.isSupportedForFileSwitching {
            activeIdentityKey = nil
            authAccessState = .unsupportedCredentialStore(
                linkedFolder: linkedLocation.folderURL,
                mode: linkedLocation.credentialStoreHint
            )
            return
        }

        let liveSnapshot: CodexAuthSnapshot
        do {
            let readResult = try await authFileManager.readAuthFile()
            liveSnapshot = try await parseSnapshot(from: readResult.contents)
        } catch let error as AuthFileAccessError {
            activeIdentityKey = nil
            applyAuthAccessState(error, linkedLocation: linkedLocation)

            if showUnexpectedErrors, Self.shouldPresentUnexpectedAuthAlert(for: error) {
                present(error, title: "Couldn't Read Codex Auth File")
            }
            return
        } catch let error as CodexAuthFileError {
            activeIdentityKey = nil
            authAccessState = .corruptAuthFile(linkedFolder: linkedLocation.folderURL)

            if showUnexpectedErrors {
                present(error, title: "Couldn't Read Codex Auth File")
            }
            return
        } catch {
            activeIdentityKey = nil

            if showUnexpectedErrors {
                present(error, title: "Couldn't Read Codex Auth File")
            }
            return
        }

        activeIdentityKey = liveSnapshot.identityKey
        authAccessState = .ready(linkedFolder: linkedLocation.folderURL)

        do {
            try await refreshStoredAccountIfKnown(from: liveSnapshot)
        } catch {
            logger.error("Live snapshot cache refresh failed: \(String(describing: error), privacy: .private)")
        }
    }

    private func preserveCurrentLiveSnapshotIfKnown() async {
        do {
            let readResult = try await authFileManager.readAuthFile()
            let snapshot = try await parseSnapshot(from: readResult.contents)
            try await refreshStoredAccountIfKnown(from: snapshot)
        } catch let error as AuthFileAccessError {
            switch error {
            case .missingAuthFile, .accessRequired, .locationUnavailable, .accessDenied, .unsupportedCredentialStore:
                return
            case .invalidSelection, .cancelled, .unreadable, .unwritable, .verificationFailed:
                return
            }
        } catch {
            return
        }
    }

    private func refreshStoredAccountIfKnown(from snapshot: CodexAuthSnapshot) async throws {
        guard let modelContext else {
            return
        }

        guard let existingAccount = try fetchAccounts().first(where: { $0.identityKey == snapshot.identityKey }) else {
            return
        }

        let didChange = await storeSnapshot(snapshot, on: existingAccount)
        if didChange {
            try modelContext.save()
        }
    }

    private func loadStoredSnapshot(for account: StoredAccount) async throws -> String {
        if let storedContents = account.authFileContents, !storedContents.isEmpty {
            await cacheSecretLocallyIfPossible(storedContents, for: account.id)
            return storedContents
        }

        let cachedContents = try await secretStore.loadSecret(for: account.id)
        if account.authFileContents != cachedContents {
            account.authFileContents = cachedContents

            do {
                try requireModelContext().save()
            } catch {
                logger.error("Couldn't backfill synced snapshot for account \(account.id.uuidString, privacy: .public): \(String(describing: error), privacy: .private)")
            }
        }

        return cachedContents
    }

    private func handleExpectedAuthOperationError(
        _ error: Error,
        title: String,
        retryAction: PendingLocationAction
    ) async {
        if let authError = error as? AuthFileAccessError {
            switch authError {
            case .accessRequired, .accessDenied, .locationUnavailable:
                pendingLocationAction = retryAction
                isShowingLocationPicker = true
                await refreshAuthState(showUnexpectedErrors: false)
                return

            case .missingAuthFile, .unsupportedCredentialStore:
                await refreshAuthState(showUnexpectedErrors: false)
                return

            case .cancelled:
                return

            case .invalidSelection, .unreadable, .unwritable, .verificationFailed:
                break
            }
        }

        if error is CodexAuthFileError {
            await refreshAuthState(showUnexpectedErrors: false)
        }

        present(error, title: title)
    }

    private func applyAuthAccessState(_ error: AuthFileAccessError, linkedLocation: AuthLinkedLocation) {
        switch error {
        case .accessRequired:
            authAccessState = .unlinked
        case let .missingAuthFile(_, credentialStoreHint):
            authAccessState = .missingAuthFile(
                linkedFolder: linkedLocation.folderURL,
                credentialStoreHint: credentialStoreHint
            )
        case let .locationUnavailable(url):
            authAccessState = .locationUnavailable(linkedFolder: url)
        case let .accessDenied(url):
            authAccessState = .accessDenied(linkedFolder: url)
        case let .unsupportedCredentialStore(url, mode):
            authAccessState = .unsupportedCredentialStore(linkedFolder: url, mode: mode)
        case .invalidSelection, .cancelled, .unreadable, .unwritable, .verificationFailed:
            authAccessState = .ready(linkedFolder: linkedLocation.folderURL)
        }
    }

    @discardableResult
    private func update(account: StoredAccount, from snapshot: CodexAuthSnapshot) -> Bool {
        var didChange = false

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

    private func bestAvailableSnapshotContents(for account: StoredAccount) async -> String? {
        if let storedContents = account.authFileContents, !storedContents.isEmpty {
            return storedContents
        }

        return try? await secretStore.loadSecret(for: account.id)
    }

    private func cacheSecretLocallyIfPossible(_ contents: String, for accountID: UUID) async {
        do {
            try await secretStore.saveSecret(contents, for: accountID)
        } catch {
            logger.error("Local keychain cache update failed for account \(accountID.uuidString, privacy: .public): \(String(describing: error), privacy: .private)")
        }
    }

    private func storeSnapshot(_ snapshot: CodexAuthSnapshot, on account: StoredAccount) async -> Bool {
        let metadataChanged = update(account: account, from: snapshot)
        let contentsChanged = account.authFileContents != snapshot.rawContents

        if contentsChanged {
            account.authFileContents = snapshot.rawContents
        }

        await cacheSecretLocallyIfPossible(snapshot.rawContents, for: account.id)
        return metadataChanged || contentsChanged
    }

    // CloudKit-backed SwiftData cannot enforce unique constraints, so the app
    // merges duplicates by identityKey when it boots with synced records.
    private func reconcileDuplicateAccountsIfNeeded() async -> Bool {
        do {
            let duplicateGroups = Dictionary(
                grouping: try fetchAccounts().filter { !$0.identityKey.isEmpty },
                by: \.identityKey
            ).values.filter { $0.count > 1 }

            guard !duplicateGroups.isEmpty else {
                return false
            }

            let modelContext = try requireModelContext()
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
                    didChange = await mergeDuplicateAccount(duplicate, into: survivor) || didChange

                    if selection.contains(duplicate.id) {
                        selection.remove(duplicate.id)
                        selection.insert(survivor.id)
                    }

                    if renameTargetID == duplicate.id {
                        renameTargetID = survivor.id
                    }

                    try? await secretStore.deleteSecret(for: duplicate.id)
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

    private func mergeDuplicateAccount(_ duplicate: StoredAccount, into survivor: StoredAccount) async -> Bool {
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

        if
            (survivor.name.isEmpty || (Self.isGeneratedAccountName(survivor.name) && !Self.isGeneratedAccountName(duplicate.name))),
            !duplicate.name.isEmpty
        {
            survivor.name = duplicate.name
            didChange = true
        }

        if (survivor.authFileContents?.isEmpty ?? true) {
            if let duplicateContents = duplicate.authFileContents, !duplicateContents.isEmpty {
                survivor.authFileContents = duplicateContents
                didChange = true
            } else if let duplicateContents = try? await secretStore.loadSecret(for: duplicate.id) {
                survivor.authFileContents = duplicateContents
                didChange = true
            }
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

        if let survivorContents = survivor.authFileContents, !survivorContents.isEmpty {
            await cacheSecretLocallyIfPossible(survivorContents, for: survivor.id)
        }

        return didChange
    }

    private func moveAccount(withID movingID: UUID, to destinationIndex: Int, visibleAccounts: [StoredAccount]) {
        guard
            let sourceIndex = visibleAccounts.firstIndex(where: { $0.id == movingID }),
            !visibleAccounts.isEmpty
        else {
            return
        }

        let boundedDestinationIndex = min(max(destinationIndex, 0), visibleAccounts.count - 1)
        guard boundedDestinationIndex != sourceIndex else {
            return
        }

        var reorderedAccounts = visibleAccounts
        let movingAccount = reorderedAccounts.remove(at: sourceIndex)
        let insertionIndex = min(max(boundedDestinationIndex, 0), reorderedAccounts.count)
        reorderedAccounts.insert(movingAccount, at: insertionIndex)

        for (index, account) in reorderedAccounts.enumerated() {
            account.customOrder = Double(index)
        }

        do {
            try requireModelContext().save()
        } catch {
            present(error, title: "Couldn't Reorder Accounts")
        }
    }

    private func fetchAccounts() throws -> [StoredAccount] {
        let modelContext = try requireModelContext()
        let descriptor = FetchDescriptor<StoredAccount>()
        return try modelContext.fetch(descriptor)
    }

    private func account(withID id: UUID) throws -> StoredAccount? {
        try fetchAccounts().first(where: { $0.id == id })
    }

    private func requireAccount(withID id: UUID) throws -> StoredAccount {
        guard let account = try account(withID: id) else {
            throw ControllerError.accountNotFound
        }

        return account
    }

    private func requireModelContext() throws -> ModelContext {
        guard let modelContext else {
            throw ControllerError.missingModelContext
        }

        return modelContext
    }

    private func present(_ error: Error, title: String) {
        guard !Self.shouldSilentlyDismiss(error) else {
            return
        }

        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        present(UserFacingAlert(title: title, message: message))
    }

    private func present(_ alert: UserFacingAlert) {
        presentedAlert = alert
    }

    private static func shouldPresentUnexpectedAuthAlert(for error: AuthFileAccessError) -> Bool {
        switch error {
        case .accessRequired, .missingAuthFile, .locationUnavailable, .accessDenied, .unsupportedCredentialStore:
            false
        case .invalidSelection, .cancelled, .unreadable, .unwritable, .verificationFailed:
            true
        }
    }

    // Cancelling the folder picker is an intentional user choice, not an error
    // that should interrupt the UI with an alert.
    private static func shouldSilentlyDismiss(_ error: Error) -> Bool {
        if let accessError = error as? AuthFileAccessError, accessError.isUserCancellation {
            return true
        }

        if error is CancellationError {
            return true
        }

        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError
    }

    private var sortComparator: (StoredAccount, StoredAccount) -> Bool {
        { [sortCriterion, sortDirection] lhs, rhs in
            let orderedAscending: Bool = switch sortCriterion {
            case .name:
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .dateAdded:
                lhs.createdAt < rhs.createdAt
            case .lastLogin:
                (lhs.lastLoginAt ?? .distantPast) < (rhs.lastLoginAt ?? .distantPast)
            case .custom:
                lhs.customOrder < rhs.customOrder
            }

            let orderedDescending: Bool = switch sortCriterion {
            case .name:
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedDescending
            case .dateAdded:
                lhs.createdAt > rhs.createdAt
            case .lastLogin:
                (lhs.lastLoginAt ?? .distantPast) > (rhs.lastLoginAt ?? .distantPast)
            case .custom:
                lhs.customOrder > rhs.customOrder
            }

            if Self.isEquivalent(lhs, rhs, for: sortCriterion) {
                return lhs.createdAt < rhs.createdAt
            }

            return sortDirection == .ascending ? orderedAscending : orderedDescending
        }
    }

    private static func isEquivalent(_ lhs: StoredAccount, _ rhs: StoredAccount, for criterion: AccountSortCriterion) -> Bool {
        switch criterion {
        case .name:
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedSame
        case .dateAdded:
            lhs.createdAt == rhs.createdAt
        case .lastLogin:
            lhs.lastLoginAt == rhs.lastLoginAt
        case .custom:
            lhs.customOrder == rhs.customOrder
        }
    }

    private static func isGeneratedAccountName(_ name: String) -> Bool {
        guard name.hasPrefix("Account ") else {
            return false
        }

        return Int(name.dropFirst("Account ".count)) != nil
    }
}

private enum PendingLocationAction {
    case captureCurrentAccount
    case switchAccount(UUID)
    case refresh
}

private enum ControllerError: LocalizedError {
    case missingModelContext
    case accountNotFound
    case accountLimitReached

    var errorDescription: String? {
        switch self {
        case .missingModelContext:
            "The app isn't ready to edit accounts yet."
        case .accountNotFound:
            "That account no longer exists."
        case .accountLimitReached:
            "Codex Switcher supports up to 1000 saved accounts."
        }
    }
}
