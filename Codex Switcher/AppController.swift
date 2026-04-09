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
    private nonisolated static let currentRateLimitDisplayVersion = 1
    private nonisolated static let currentAccountRateLimitRefreshInterval: TimeInterval = 60
    private nonisolated static let visibleAccountRateLimitRefreshInterval: TimeInterval = 5 * 60
    private nonisolated static let rateLimitPollingCadence: Duration = .seconds(5)
    private nonisolated static let initialRateLimitFailureBackoff: TimeInterval = 60
    private nonisolated static let maximumRateLimitFailureBackoff: TimeInterval = 15 * 60

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
    @ObservationIgnored private let rateLimitProvider: CodexRateLimitProviding
    @ObservationIgnored private let logger: Logger
    @ObservationIgnored private let startupAlert: UserFacingAlert?

    @ObservationIgnored private var modelContainer: ModelContainer?
    @ObservationIgnored private var hasConfiguredInitialState = false
    @ObservationIgnored private var hasStartedMonitoring = false
    @ObservationIgnored private var pendingLocationAction: PendingLocationAction?
    @ObservationIgnored private var initializationTask: Task<Void, Never>?
    @ObservationIgnored private var switchTask: Task<Void, Never>?
    @ObservationIgnored private var activeSwitchOperationID: UUID?
    @ObservationIgnored private var remoteSwitchObserver: NSObjectProtocol?
    @ObservationIgnored private var sharedStatePublishTask: Task<Void, Never>?
    @ObservationIgnored private var rateLimitPollingTask: Task<Void, Never>?
    @ObservationIgnored private var rateLimitSnapshotsByIdentityKey: [String: CodexRateLimitSnapshot] = [:]
    @ObservationIgnored private var visibleRateLimitIdentityCounts: [String: Int] = [:]
    @ObservationIgnored private var pendingForcedRateLimitRefreshes: Set<String> = []
    @ObservationIgnored private var rateLimitRefreshesInFlight: Set<String> = []
    @ObservationIgnored private var rateLimitFailureBackoffUntil: [String: Date] = [:]
    @ObservationIgnored private var rateLimitFailureBackoffDurations: [String: TimeInterval] = [:]
    @ObservationIgnored private var isApplicationActive = false
    @ObservationIgnored private var isMenuBarPresented = false

    init(
        authFileManager: AuthFileManaging,
        secretStore: AccountSecretStoring,
        notificationManager: AccountSwitchNotifying,
        rateLimitProvider: CodexRateLimitProviding = CodexRateLimitProvider(),
        startupAlert: UserFacingAlert? = nil,
        modelContainer: ModelContainer? = nil,
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "CodexSwitcher"
    ) {
        self.authFileManager = authFileManager
        self.secretStore = secretStore
        self.notificationManager = notificationManager
        self.rateLimitProvider = rateLimitProvider
        self.startupAlert = startupAlert
        self.modelContainer = modelContainer
        self.logger = Logger(subsystem: bundleIdentifier, category: "AppController")
    }

    deinit {
        initializationTask?.cancel()
        switchTask?.cancel()
        sharedStatePublishTask?.cancel()
        rateLimitPollingTask?.cancel()
    }

    func configure(modelContext: ModelContext, undoManager: UndoManager?) {
        // Scene environment contexts can be recreated as windows and menu-bar
        // scenes appear or disappear. Persist the owning container instead of
        // holding onto a scene-scoped ModelContext reference that may no longer
        // be valid when an async refresh fires later.
        if modelContainer == nil {
            modelContainer = modelContext.container
        }

        let resolvedModelContext = modelContainer?.mainContext ?? modelContext
        if let undoManager {
            resolvedModelContext.undoManager = undoManager
        }

        guard !hasConfiguredInitialState else {
            return
        }

        hasConfiguredInitialState = true
        startObservingRemoteSwitchesIfNeeded()

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
            self.publishSharedState()
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

    var hasSavedAccounts: Bool {
        ((try? !fetchAccounts().isEmpty) == true)
    }

    // Sort preferences are persisted by the SwiftUI app layer with AppStorage.
    // Restore them here so unknown raw values degrade to safe defaults instead
    // of leaving the controller in an invalid state.
    func restoreSortPreferences(
        sortCriterionRawValue: String,
        sortDirectionRawValue: String
    ) {
        let resolvedCriterion = AccountSortCriterion(rawValue: sortCriterionRawValue) ?? .dateAdded
        let resolvedDirection = SortDirection(rawValue: sortDirectionRawValue) ?? .ascending

        if sortCriterion != resolvedCriterion {
            sortCriterion = resolvedCriterion
        }

        if sortDirection != resolvedDirection {
            sortDirection = resolvedDirection
        }
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

    func setApplicationActive(_ isActive: Bool) {
        guard isApplicationActive != isActive else {
            return
        }

        isApplicationActive = isActive
        updateRateLimitPollingState()

        if isRateLimitSurfaceActive {
            requestImmediateRateLimitRefreshForVisibleAccounts()
        }
    }

    func setMenuBarPresented(_ isPresented: Bool) {
        guard isMenuBarPresented != isPresented else {
            return
        }

        isMenuBarPresented = isPresented
        updateRateLimitPollingState()

        if isRateLimitSurfaceActive {
            requestImmediateRateLimitRefreshForVisibleAccounts()
        }
    }

    func setRateLimitVisibility(_ isVisible: Bool, for identityKey: String) {
        guard !identityKey.isEmpty else {
            return
        }

        let currentCount = visibleRateLimitIdentityCounts[identityKey] ?? 0
        let updatedCount = isVisible ? currentCount + 1 : max(currentCount - 1, 0)

        if updatedCount == 0 {
            visibleRateLimitIdentityCounts.removeValue(forKey: identityKey)
        } else {
            visibleRateLimitIdentityCounts[identityKey] = updatedCount
        }

        updateRateLimitPollingState()

        if isVisible, isRateLimitSurfaceActive {
            requestImmediateRateLimitRefresh(for: identityKey)
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

        return sortedAccounts(from: filteredAccounts)
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

            await self.performRefresh(showUnexpectedErrors: true)
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
            publishSharedState()
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
            publishSharedState()
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

    func removeAllAccounts() {
        Task { [weak self] in
            guard let self else {
                return
            }

            await self.removeAllAccountsNow()
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
                    name: defaultName(for: snapshot, existingAccounts: accounts),
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
            publishSharedState()
            requestImmediateRateLimitRefresh(for: snapshot.identityKey)
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

            publishSharedState()
            requestImmediateRateLimitRefresh(for: targetAccount.identityKey)
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
            let deletedIdentityKeys = Set(
                accountsToDelete
                    .map(\.identityKey)
                    .filter { !$0.isEmpty }
            )

            for account in accountsToDelete {
                try? await secretStore.deleteSecret(for: account.id)
                modelContext.delete(account)
            }

            selection.subtract(ids)
            if let renameTargetID, ids.contains(renameTargetID) {
                self.renameTargetID = nil
            }

            for identityKey in deletedIdentityKeys {
                rateLimitSnapshotsByIdentityKey.removeValue(forKey: identityKey)
                visibleRateLimitIdentityCounts.removeValue(forKey: identityKey)
                pendingForcedRateLimitRefreshes.remove(identityKey)
                rateLimitRefreshesInFlight.remove(identityKey)
                rateLimitFailureBackoffUntil.removeValue(forKey: identityKey)
                rateLimitFailureBackoffDurations.removeValue(forKey: identityKey)
            }

            try modelContext.save()
            publishSharedState()
        } catch {
            present(error, title: "Couldn't Remove Account")
        }
    }

    func removeAllAccountsNow() async {
        await waitForInitializationIfNeeded()

        do {
            let allAccountIDs = Set(try fetchAccounts().map(\.id))
            await removeAccountsNow(withIDs: allAccountIDs)
        } catch {
            present(error, title: "Couldn't Remove Accounts")
        }
    }

    func refreshAuthStateForTesting() async {
        await waitForInitializationIfNeeded()
        await refreshAuthState(showUnexpectedErrors: false)
    }

    func refreshForTesting() async {
        await performRefresh(showUnexpectedErrors: true)
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

    private func performRefresh(showUnexpectedErrors: Bool) async {
        await waitForInitializationIfNeeded()
        await refreshAuthState(showUnexpectedErrors: showUnexpectedErrors)
        await refreshVisibleRateLimitsImmediatelyIfPossible()
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

    private func startObservingRemoteSwitchesIfNeeded() {
        guard remoteSwitchObserver == nil else {
            return
        }

        remoteSwitchObserver = DistributedNotificationCenter.default().addObserver(
            forName: CodexSharedSwitchFeedback.didSwitchAccountNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let self,
                let signal = CodexSharedSwitchFeedback.signal(from: notification)
            else {
                return
            }

            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                await self.handleRemoteSwitchSignal(signal)
            }
        }
    }

    private func handleRemoteSwitchSignal(_ signal: CodexSharedSwitchSignal) async {
        await waitForInitializationIfNeeded()
        await refreshAuthState(showUnexpectedErrors: false)

        do {
            if let switchedAccount = try fetchAccounts().first(where: { $0.identityKey == signal.identityKey }) {
                selection = [switchedAccount.id]
                renameTargetID = nil
            }
        } catch {
            logger.error(
                "Couldn't apply remote account switch selection for \(signal.identityKey, privacy: .public): \(String(describing: error), privacy: .private)"
            )
        }

        // The intent path already delivers its own confirmation. Refresh the
        // app state here without posting a second banner from the app process.
        requestImmediateRateLimitRefresh(for: signal.identityKey)
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
            await performRefresh(showUnexpectedErrors: true)
        }
    }

    private func reconcileStoredSnapshotsIfNeeded() async {
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
                    if let syncedContents = account.authFileContents, !syncedContents.isEmpty {
                        // Backfill the local keychain cache once during startup
                        // reconciliation so older synced records still work
                        // offline, without paying this cost on every switch.
                        await cacheSecretLocallyIfPossible(syncedContents, for: account.id)
                    }
                } catch {
                    logger.error("Stored snapshot reconciliation failed for account \(account.id.uuidString, privacy: .public): \(String(describing: error), privacy: .private)")
                }
            }

            didChange = await reconcileDuplicateAccountsIfNeeded() || didChange

            if didChange {
                try requireModelContext().save()
            }
        } catch {
            present(error, title: "Couldn't Upgrade Saved Accounts")
        }
    }

    private func reconcileDisplayOnlyFieldsIfNeeded() {
        do {
            var didChange = false

            for account in try fetchAccounts() {
                if account.iconSystemName.isEmpty {
                    account.iconSystemName = AccountIconOption.defaultOption.systemName
                    didChange = true
                }

                if account.rateLimitDisplayVersion != Self.currentRateLimitDisplayVersion {
                    if let sevenDayUsedPercent = account.sevenDayLimitUsedPercent {
                        account.sevenDayLimitUsedPercent = 100 - min(max(sevenDayUsedPercent, 0), 100)
                        didChange = true
                    }

                    if let fiveHourUsedPercent = account.fiveHourLimitUsedPercent {
                        account.fiveHourLimitUsedPercent = 100 - min(max(fiveHourUsedPercent, 0), 100)
                        didChange = true
                    }

                    account.rateLimitDisplayVersion = Self.currentRateLimitDisplayVersion
                    didChange = true
                }
            }

            if didChange {
                try requireModelContext().save()
            }
        } catch {
            present(error, title: "Couldn't Refresh Saved Accounts")
        }
    }

    private func refreshAuthState(showUnexpectedErrors: Bool) async {
        defer { publishSharedState() }

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

        let liveReadResult: AuthFileReadResult
        let liveSnapshot: CodexAuthSnapshot
        do {
            liveReadResult = try await authFileManager.readAuthFile()
            liveSnapshot = try await parseSnapshot(from: liveReadResult.contents)
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
            try await refreshStoredAccountIfKnown(from: liveSnapshot, authFileURL: liveReadResult.url)
        } catch {
            logger.error("Live snapshot cache refresh failed: \(String(describing: error), privacy: .private)")
        }

        requestImmediateRateLimitRefresh(for: liveSnapshot.identityKey)
    }

    private func preserveCurrentLiveSnapshotIfKnown() async {
        do {
            let readResult = try await authFileManager.readAuthFile()
            let snapshot = try await parseSnapshot(from: readResult.contents)
            try await refreshStoredAccountIfKnown(from: snapshot, authFileURL: readResult.url)
            requestImmediateRateLimitRefresh(for: snapshot.identityKey)
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

    private func refreshStoredAccountIfKnown(from snapshot: CodexAuthSnapshot, authFileURL: URL) async throws {
        guard let existingAccount = try fetchAccounts().first(where: { $0.identityKey == snapshot.identityKey }) else {
            return
        }

        let didChange = await storeSnapshot(snapshot, on: existingAccount)
        if didChange {
            try requireModelContext().save()
        }
    }

    private func loadStoredSnapshot(for account: StoredAccount) async throws -> String {
        if let storedContents = account.authFileContents, !storedContents.isEmpty {
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

    private var isRateLimitSurfaceActive: Bool {
        isApplicationActive || isMenuBarPresented
    }

    private func requestImmediateRateLimitRefresh(for identityKey: String) {
        requestImmediateRateLimitRefresh(for: [identityKey])
    }

    private func requestImmediateRateLimitRefreshForVisibleAccounts() {
        requestImmediateRateLimitRefresh(for: visibleRateLimitRefreshIdentityKeys())
    }

    // Manual and user-driven refresh triggers should bypass the normal polling
    // window and any temporary failure backoff, but still coalesce per-account
    // work so repeated focus/open events do not fan out into duplicate requests.
    private func requestImmediateRateLimitRefresh(for identityKeys: [String]) {
        let identities = normalizedRateLimitIdentityKeys(identityKeys)
        guard !identities.isEmpty else {
            return
        }

        for identityKey in identities {
            pendingForcedRateLimitRefreshes.insert(identityKey)
            rateLimitFailureBackoffUntil.removeValue(forKey: identityKey)
        }

        updateRateLimitPollingState()

        guard isRateLimitSurfaceActive else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            await self.refreshRateLimitsImmediately(for: identities)
        }
    }

    private func normalizedRateLimitIdentityKeys(_ identityKeys: [String]) -> [String] {
        var normalized: [String] = []
        var seen = Set<String>()

        for identityKey in identityKeys {
            let trimmedIdentityKey = identityKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedIdentityKey.isEmpty, !seen.contains(trimmedIdentityKey) else {
                continue
            }

            normalized.append(trimmedIdentityKey)
            seen.insert(trimmedIdentityKey)
        }

        return normalized
    }

    private func refreshRateLimitsImmediately(for identityKeys: [String]) async {
        for identityKey in normalizedRateLimitIdentityKeys(identityKeys) {
            await refreshRateLimitsNow(for: identityKey)
        }
    }

    private func visibleRateLimitRefreshIdentityKeys() -> [String] {
        var identities: [String] = []
        var seen = Set<String>()

        if let activeIdentityKey, !activeIdentityKey.isEmpty {
            identities.append(activeIdentityKey)
            seen.insert(activeIdentityKey)
        }

        for identityKey in visibleRateLimitIdentityCounts.keys.sorted() where !identityKey.isEmpty && !seen.contains(identityKey) {
            identities.append(identityKey)
            seen.insert(identityKey)
        }

        return identities
    }

    private func refreshVisibleRateLimitsImmediatelyIfPossible() async {
        let identities = visibleRateLimitRefreshIdentityKeys()
        guard !identities.isEmpty else {
            return
        }

        for identityKey in identities {
            pendingForcedRateLimitRefreshes.insert(identityKey)
            rateLimitFailureBackoffUntil.removeValue(forKey: identityKey)
        }

        updateRateLimitPollingState()

        guard isRateLimitSurfaceActive else {
            return
        }

        await refreshRateLimitsImmediately(for: identities)
    }

    private func updateRateLimitPollingState() {
        guard isRateLimitSurfaceActive, !rateLimitCandidateIdentityKeys().isEmpty else {
            rateLimitPollingTask?.cancel()
            rateLimitPollingTask = nil
            return
        }

        guard rateLimitPollingTask == nil else {
            return
        }

        rateLimitPollingTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            await self.runRateLimitPollingLoop()
        }
    }

    // Poll only while the user can currently see the app or its menu bar
    // window. The actual request spacing is enforced lower down by the rate-
    // limit provider's request limiter.
    private func runRateLimitPollingLoop() async {
        defer {
            rateLimitPollingTask = nil
        }

        while isRateLimitSurfaceActive, !Task.isCancelled {
            await refreshDueRateLimitsIfNeeded()

            if !isRateLimitSurfaceActive {
                break
            }

            try? await Task.sleep(for: Self.rateLimitPollingCadence)
        }
    }

    private func refreshDueRateLimitsIfNeeded() async {
        guard isRateLimitSurfaceActive else {
            return
        }

        let now = Date()
        applyLocalRateLimitResetsIfNeeded(relativeTo: now)

        let identities = rateLimitCandidateIdentityKeys()
        guard !identities.isEmpty else {
            return
        }

        for identityKey in identities {
            guard shouldRefreshRateLimits(for: identityKey, relativeTo: now) else {
                continue
            }

            await refreshRateLimitsNow(for: identityKey)
        }
    }

    private func refreshRateLimitsNow(for identityKey: String) async {
        guard !rateLimitRefreshesInFlight.contains(identityKey) else {
            return
        }

        rateLimitRefreshesInFlight.insert(identityKey)
        defer {
            rateLimitRefreshesInFlight.remove(identityKey)
        }

        guard let account = try? fetchAccounts().first(where: { $0.identityKey == identityKey }) else {
            pendingForcedRateLimitRefreshes.remove(identityKey)
            return
        }

        let linkedLocation = identityKey == activeIdentityKey ? await authFileManager.linkedLocation() : nil
        let request = CodexRateLimitRequest(
            identityKey: identityKey,
            authFileContents: await bestAvailableSnapshotContents(for: account),
            linkedLocation: linkedLocation,
            isCurrentAccount: identityKey == activeIdentityKey
        )

        let snapshot = await rateLimitProvider.fetchSnapshot(for: request)
        pendingForcedRateLimitRefreshes.remove(identityKey)

        do {
            guard let account = try fetchAccounts().first(where: { $0.identityKey == identityKey }) else {
                return
            }

            if let snapshot {
                let adjustedSnapshot = snapshot.applyingResetBoundaries()
                guard shouldReplaceExistingRateLimitSnapshot(adjustedSnapshot, for: identityKey) else {
                    return
                }

                rateLimitSnapshotsByIdentityKey[identityKey] = adjustedSnapshot
                rateLimitFailureBackoffUntil.removeValue(forKey: identityKey)
                rateLimitFailureBackoffDurations.removeValue(forKey: identityKey)

                guard update(account: account, from: adjustedSnapshot) else {
                    return
                }

                try requireModelContext().save()
                publishSharedState()
            } else {
                let currentBackoff = rateLimitFailureBackoffDurations[identityKey] ?? Self.initialRateLimitFailureBackoff
                rateLimitFailureBackoffUntil[identityKey] = Date().addingTimeInterval(currentBackoff)
                rateLimitFailureBackoffDurations[identityKey] = min(
                    currentBackoff * 2,
                    Self.maximumRateLimitFailureBackoff
                )
            }
        } catch {
            logger.error("Rate-limit refresh failed for account \(identityKey, privacy: .private): \(String(describing: error), privacy: .private)")
        }
    }

    private func applyLocalRateLimitResetsIfNeeded(relativeTo now: Date) {
        do {
            // If the server already told us an exact reset timestamp, we can
            // flip the UI back to 100% locally instead of waiting for the next
            // network round-trip.
            var didChange = false
            let accountsByIdentityKey = Dictionary(
                uniqueKeysWithValues: try fetchAccounts().map { ($0.identityKey, $0) }
            )

            for identityKey in rateLimitCandidateIdentityKeys() {
                guard
                    let existingSnapshot = rateLimitSnapshotsByIdentityKey[identityKey],
                    let account = accountsByIdentityKey[identityKey]
                else {
                    continue
                }

                let adjustedSnapshot = existingSnapshot.applyingResetBoundaries(relativeTo: now)
                guard adjustedSnapshot != existingSnapshot else {
                    continue
                }

                rateLimitSnapshotsByIdentityKey[identityKey] = adjustedSnapshot
                didChange = update(account: account, from: adjustedSnapshot) || didChange
            }

            if didChange {
                try requireModelContext().save()
                publishSharedState()
            }
        } catch {
            logger.error("Local rate-limit reset handling failed: \(String(describing: error), privacy: .private)")
        }
    }

    private func shouldRefreshRateLimits(for identityKey: String, relativeTo now: Date) -> Bool {
        if pendingForcedRateLimitRefreshes.contains(identityKey) {
            return true
        }

        if let backoffUntil = rateLimitFailureBackoffUntil[identityKey], backoffUntil > now {
            return false
        }

        let refreshInterval = identityKey == activeIdentityKey
            ? Self.currentAccountRateLimitRefreshInterval
            : Self.visibleAccountRateLimitRefreshInterval

        if let snapshot = rateLimitSnapshotsByIdentityKey[identityKey] {
            if let nextResetAt = snapshot.nextResetAt, now >= nextResetAt {
                return true
            }

            return now.timeIntervalSince(snapshot.fetchedAt) >= refreshInterval
        }

        do {
            if let account = try fetchAccounts().first(where: { $0.identityKey == identityKey }) {
                if let observedAt = account.rateLimitsObservedAt {
                    return now.timeIntervalSince(observedAt) >= refreshInterval
                }
            }
        } catch {
            return true
        }

        return true
    }

    private func shouldReplaceExistingRateLimitSnapshot(
        _ snapshot: CodexRateLimitSnapshot,
        for identityKey: String
    ) -> Bool {
        guard let existingSnapshot = rateLimitSnapshotsByIdentityKey[identityKey] else {
            return true
        }

        if snapshot.observedAt > existingSnapshot.observedAt {
            return true
        }

        if snapshot.observedAt < existingSnapshot.observedAt {
            return false
        }

        if snapshot.source.priority != existingSnapshot.source.priority {
            return snapshot.source.priority > existingSnapshot.source.priority
        }

        return snapshot.fetchedAt >= existingSnapshot.fetchedAt
    }

    private func rateLimitCandidateIdentityKeys() -> [String] {
        var identities: [String] = []
        var seen = Set<String>()

        if let activeIdentityKey, !activeIdentityKey.isEmpty {
            identities.append(activeIdentityKey)
            seen.insert(activeIdentityKey)
        }

        for identityKey in visibleRateLimitIdentityCounts.keys.sorted() where !identityKey.isEmpty && !seen.contains(identityKey) {
            identities.append(identityKey)
            seen.insert(identityKey)
        }

        for identityKey in pendingForcedRateLimitRefreshes.sorted() where !identityKey.isEmpty && !seen.contains(identityKey) {
            identities.append(identityKey)
        }

        return identities
    }

    private func storeSnapshot(
        _ snapshot: CodexAuthSnapshot,
        rateLimitObservation: CodexRateLimitObservation? = nil,
        on account: StoredAccount
    ) async -> Bool {
        let metadataChanged = update(account: account, from: snapshot)
        let contentsChanged = account.authFileContents != snapshot.rawContents
        let rateLimitsChanged = update(account: account, from: rateLimitObservation)

        if contentsChanged {
            account.authFileContents = snapshot.rawContents
            // Avoid rewriting the local keychain cache on every refresh or
            // switch. Keychain writes are relatively expensive, and the synced
            // snapshot already remains available in SwiftData for normal reads.
            await cacheSecretLocallyIfPossible(snapshot.rawContents, for: account.id)
        }

        return metadataChanged || contentsChanged || rateLimitsChanged
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

        if (duplicate.rateLimitsObservedAt ?? .distantPast) > (survivor.rateLimitsObservedAt ?? .distantPast) {
            survivor.rateLimitsObservedAt = duplicate.rateLimitsObservedAt
            survivor.sevenDayLimitUsedPercent = duplicate.sevenDayLimitUsedPercent
            survivor.fiveHourLimitUsedPercent = duplicate.fiveHourLimitUsedPercent
            survivor.rateLimitDisplayVersion = duplicate.rateLimitDisplayVersion
            didChange = true
        }

        if survivor.rateLimitDisplayVersion == nil, duplicate.rateLimitDisplayVersion != nil {
            survivor.rateLimitDisplayVersion = duplicate.rateLimitDisplayVersion
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
            publishSharedState()
        } catch {
            present(error, title: "Couldn't Reorder Accounts")
        }
    }

    private func sortedAccounts(from accounts: [StoredAccount]) -> [StoredAccount] {
        accounts.sorted(by: sortComparator)
    }

    private func publishSharedState() {
        let sharedState: SharedCodexState
        do {
            sharedState = try makeSharedState()
        } catch {
            logger.error("Couldn't prepare shared widget state: \(String(describing: error), privacy: .private)")
            return
        }

        sharedStatePublishTask?.cancel()
        sharedStatePublishTask = Task.detached(priority: .utility) {
            do {
                try? await Task.sleep(for: .milliseconds(150))
                try Task.checkCancellation()
                try CodexSharedStateStore().save(sharedState)
                CodexSharedSurfaceReloader.reloadAll()
            } catch is CancellationError {
                return
            } catch {
                let logger = Logger(
                    subsystem: Bundle.main.bundleIdentifier ?? "CodexSwitcher",
                    category: "SharedState"
                )
                logger.error("Couldn't publish shared widget state: \(String(describing: error), privacy: .private)")
            }
        }
    }

    private func makeSharedState() throws -> SharedCodexState {
        let allAccounts = try fetchAccounts()
        let sharedAccounts = sortedAccounts(from: allAccounts)
            .filter { !$0.identityKey.isEmpty }
            .map { account in
                SharedCodexAccountRecord(
                    id: account.identityKey,
                    name: account.name,
                    iconSystemName: account.iconSystemName,
                    emailHint: account.emailHint,
                    accountIdentifier: account.accountIdentifier,
                    authModeRaw: account.authModeRaw,
                    lastLoginAt: account.lastLoginAt,
                    sevenDayLimitUsedPercent: account.sevenDayLimitUsedPercent,
                    fiveHourLimitUsedPercent: account.fiveHourLimitUsedPercent,
                    rateLimitsObservedAt: account.rateLimitsObservedAt,
                    sortOrder: account.customOrder,
                    authFileContents: account.authFileContents
                )
            }

        return SharedCodexState(
            schemaVersion: SharedCodexState.currentSchemaVersion,
            authState: SharedCodexAuthState(authAccessState: authAccessState),
            linkedFolderPath: linkedFolderPath,
            currentAccountID: activeIdentityKey,
            accounts: sharedAccounts,
            updatedAt: .now
        )
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
        guard let modelContainer else {
            throw ControllerError.missingModelContext
        }

        return modelContainer.mainContext
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
            if sortCriterion == .rateLimit {
                if Self.areEquivalentForRateLimitSort(lhs, rhs, direction: sortDirection) {
                    return lhs.createdAt < rhs.createdAt
                }

                return Self.rateLimitSortComesBefore(lhs, rhs, direction: sortDirection)
            }

            let orderedAscending: Bool = switch sortCriterion {
            case .name:
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .dateAdded:
                lhs.createdAt < rhs.createdAt
            case .lastLogin:
                (lhs.lastLoginAt ?? .distantPast) < (rhs.lastLoginAt ?? .distantPast)
            case .rateLimit:
                false
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
            case .rateLimit:
                false
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
        case .rateLimit:
            false
        case .custom:
            lhs.customOrder == rhs.customOrder
        }
    }

    // "Rate Limit" always sorts by the tighter remaining bucket, which is the
    // minimum of the currently known 5h and 7d percentages. Unknown values
    // always sort after known accounts so "?" rows don't jump ahead.
    private static func rateLimitSortComesBefore(
        _ lhs: StoredAccount,
        _ rhs: StoredAccount,
        direction: SortDirection
    ) -> Bool {
        let lhsMetrics = rateLimitSortMetrics(for: lhs, direction: direction)
        let rhsMetrics = rateLimitSortMetrics(for: rhs, direction: direction)

        switch (lhsMetrics.primary, rhsMetrics.primary) {
        case let (lhsPrimary?, rhsPrimary?):
            if lhsPrimary != rhsPrimary {
                return direction == .ascending ? lhsPrimary < rhsPrimary : lhsPrimary > rhsPrimary
            }
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            return lhs.createdAt < rhs.createdAt
        }

        switch (lhsMetrics.secondary, rhsMetrics.secondary) {
        case let (lhsSecondary?, rhsSecondary?):
            if lhsSecondary != rhsSecondary {
                return direction == .ascending ? lhsSecondary < rhsSecondary : lhsSecondary > rhsSecondary
            }
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            break
        }

        return lhs.createdAt < rhs.createdAt
    }

    private static func areEquivalentForRateLimitSort(
        _ lhs: StoredAccount,
        _ rhs: StoredAccount,
        direction: SortDirection
    ) -> Bool {
        let lhsMetrics = rateLimitSortMetrics(for: lhs, direction: direction)
        let rhsMetrics = rateLimitSortMetrics(for: rhs, direction: direction)
        return lhsMetrics.primary == rhsMetrics.primary
            && lhsMetrics.secondary == rhsMetrics.secondary
    }

    private static func rateLimitSortMetrics(
        for account: StoredAccount,
        direction: SortDirection
    ) -> (primary: Int?, secondary: Int?) {
        let primary = normalizedRateLimitValues(for: account).min()
        guard let primary else {
            return (nil, nil)
        }

        return (primary, nil)
    }

    private static func normalizedRateLimitValues(for account: StoredAccount) -> [Int] {
        [account.fiveHourLimitUsedPercent, account.sevenDayLimitUsedPercent]
            .compactMap { $0 }
            .map { min(max($0, 0), 100) }
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

    private func defaultName(for snapshot: CodexAuthSnapshot, existingAccounts: [StoredAccount]) -> String {
        if let preferredEmail = snapshot.email?.trimmingCharacters(in: .whitespacesAndNewlines), !preferredEmail.isEmpty {
            return preferredEmail
        }

        return nextGeneratedAccountName(existingAccounts: existingAccounts)
    }

    private func nextGeneratedAccountName(existingAccounts: [StoredAccount]) -> String {
        let usedIndices = Set(existingAccounts.compactMap { Self.generatedAccountIndex(from: $0.name) })

        var candidateIndex = 1
        while usedIndices.contains(candidateIndex) {
            candidateIndex += 1
        }

        return "Account \(candidateIndex)"
    }

    @discardableResult
    private func update(account: StoredAccount, from rateLimitSnapshot: CodexRateLimitSnapshot?) -> Bool {
        guard let rateLimitSnapshot else {
            return false
        }

        let existingObservedAt = account.rateLimitsObservedAt ?? .distantPast
        guard rateLimitSnapshot.observedAt >= existingObservedAt else {
            return false
        }

        var didChange = false

        if account.rateLimitsObservedAt != rateLimitSnapshot.observedAt {
            account.rateLimitsObservedAt = rateLimitSnapshot.observedAt
            didChange = true
        }

        if account.sevenDayLimitUsedPercent != rateLimitSnapshot.sevenDayRemainingPercent {
            account.sevenDayLimitUsedPercent = rateLimitSnapshot.sevenDayRemainingPercent
            didChange = true
        }

        if account.fiveHourLimitUsedPercent != rateLimitSnapshot.fiveHourRemainingPercent {
            account.fiveHourLimitUsedPercent = rateLimitSnapshot.fiveHourRemainingPercent
            didChange = true
        }

        if account.rateLimitDisplayVersion != Self.currentRateLimitDisplayVersion {
            account.rateLimitDisplayVersion = Self.currentRateLimitDisplayVersion
            didChange = true
        }

        return didChange
    }

    @discardableResult
    private func update(account: StoredAccount, from rateLimitObservation: CodexRateLimitObservation?) -> Bool {
        guard let rateLimitObservation else {
            return false
        }

        let existingObservedAt = account.rateLimitsObservedAt ?? .distantPast
        guard rateLimitObservation.observedAt >= existingObservedAt else {
            return false
        }

        var didChange = false

        if account.rateLimitsObservedAt != rateLimitObservation.observedAt {
            account.rateLimitsObservedAt = rateLimitObservation.observedAt
            didChange = true
        }

        if account.sevenDayLimitUsedPercent != rateLimitObservation.sevenDayRemainingPercent {
            account.sevenDayLimitUsedPercent = rateLimitObservation.sevenDayRemainingPercent
            didChange = true
        }

        if account.fiveHourLimitUsedPercent != rateLimitObservation.fiveHourRemainingPercent {
            account.fiveHourLimitUsedPercent = rateLimitObservation.fiveHourRemainingPercent
            didChange = true
        }

        if account.rateLimitDisplayVersion != Self.currentRateLimitDisplayVersion {
            account.rateLimitDisplayVersion = Self.currentRateLimitDisplayVersion
            didChange = true
        }

        return didChange
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

private extension SharedCodexAuthState {
    init(authAccessState: AuthAccessState) {
        switch authAccessState {
        case .unlinked:
            self = .unlinked
        case .ready:
            self = .ready
        case .missingAuthFile:
            self = .loggedOut
        case .locationUnavailable:
            self = .locationUnavailable
        case .accessDenied:
            self = .accessDenied
        case .corruptAuthFile:
            self = .corruptAuthFile
        case .unsupportedCredentialStore:
            self = .unsupportedCredentialStore
        }
    }
}
