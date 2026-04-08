//
//  AppController.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-07.
//

import Combine
import Foundation
import SwiftData
import SwiftUI

struct UserFacingAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

@MainActor
final class AppController: ObservableObject {
    @Published var selection: Set<UUID> = []
    @Published var searchText = ""
    @Published var sortCriterion: AccountSortCriterion = .dateAdded
    @Published var sortDirection: SortDirection = .ascending
    @Published var renameTargetID: UUID?
    @Published var presentedAlert: UserFacingAlert?
    @Published private(set) var activeIdentityKey: String?

    private let authFileManager: AuthFileManaging
    private let notificationManager: AccountSwitchNotifying
    private var modelContext: ModelContext?
    private var hasReconciledStoredAccounts = false

    init(
        authFileManager: AuthFileManaging,
        notificationManager: AccountSwitchNotifying
    ) {
        self.authFileManager = authFileManager
        self.notificationManager = notificationManager
    }

    func configure(modelContext: ModelContext, undoManager: UndoManager?) {
        self.modelContext = modelContext
        modelContext.undoManager = undoManager

        guard !hasReconciledStoredAccounts else {
            return
        }

        reconcileStoredAccountsIfNeeded()
        hasReconciledStoredAccounts = true
    }

    var canEditCustomOrder: Bool {
        sortCriterion == .custom && searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    func refreshActiveAccountIndicator(promptIfNeeded: Bool) {
        do {
            let readResult = try authFileManager.readAuthFile(promptIfNeeded: promptIfNeeded)
            let snapshot = try CodexAuthFile.parse(contents: readResult.contents)
            activeIdentityKey = snapshot.identityKey
        } catch let error as AuthFileAccessError where error.isMissingAuthFile {
            activeIdentityKey = nil
        } catch {
            if promptIfNeeded {
                present(error, title: "Couldn't Read Codex Auth File")
            }
        }
    }

    func captureCurrentAccount() {
        do {
            let modelContext = try requireModelContext()
            let readResult = try authFileManager.readAuthFile(promptIfNeeded: true)
            let snapshot = try CodexAuthFile.parse(contents: readResult.contents)
            let accounts = try fetchAccounts()

            if let existingAccount = accounts.first(where: { $0.identityKey == snapshot.identityKey }) {
                update(account: existingAccount, from: snapshot)
                selection = [existingAccount.id]
            } else {
                guard accounts.count < 1_000 else {
                    throw ControllerError.accountLimitReached
                }

                let nextCustomOrder = (accounts.map(\.customOrder).max() ?? -1) + 1
                let account = StoredAccount(
                    identityKey: snapshot.identityKey,
                    name: "Unnamed Account \(accounts.count + 1)",
                    customOrder: nextCustomOrder,
                    authFileContents: snapshot.rawContents,
                    authModeRaw: snapshot.authMode.rawValue,
                    emailHint: snapshot.email,
                    accountIdentifier: snapshot.accountIdentifier
                )

                modelContext.insert(account)
                selection = [account.id]
            }

            try modelContext.save()
            searchText = ""
            activeIdentityKey = snapshot.identityKey
        } catch {
            present(error, title: "Couldn't Save Account")
        }
    }

    func login(accountID: UUID) {
        Task {
            await switchToAccount(id: accountID)
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

    func cancelRename(for accountID: UUID) {
        guard renameTargetID == accountID else {
            return
        }
        renameTargetID = nil
    }

    func commitRename(for accountID: UUID, proposedName: String) {
        guard let account = try? account(withID: accountID) else {
            renameTargetID = nil
            return
        }

        let trimmedName = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            account.name = trimmedName
            try? modelContext?.save()
        }

        renameTargetID = nil
    }

    func removeSelectedAccounts() {
        removeAccounts(withIDs: selection)
    }

    func removeAccounts(withIDs ids: Set<UUID>) {
        guard !ids.isEmpty else {
            return
        }

        do {
            let modelContext = try requireModelContext()
            for account in try fetchAccounts().filter({ ids.contains($0.id) }) {
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

        // Drop destinations are insertion points in the pre-move list, while
        // moveAccount expects the final row index after the item is removed.
        if sourceIndex < boundedDropIndex {
            finalIndex -= 1
        }

        finalIndex = min(max(finalIndex, 0), max(visibleAccounts.count - 1, 0))

        Task { @MainActor in
            moveAccount(withID: movingID, to: finalIndex, visibleAccounts: visibleAccounts)
        }
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

    private func switchToAccount(id: UUID) async {
        do {
            let modelContext = try requireModelContext()
            let targetAccount = try requireAccount(withID: id)
            var desiredAuthFileContents = targetAccount.authFileContents
            let currentReadResult: AuthFileReadResult?
            do {
                currentReadResult = try authFileManager.readAuthFile(promptIfNeeded: true)
            } catch let error as AuthFileAccessError where error.isMissingAuthFile {
                currentReadResult = nil
            }

            if let currentReadResult,
               let currentSnapshot = try? CodexAuthFile.parse(contents: currentReadResult.contents),
               let existingCurrentAccount = try fetchAccounts().first(where: { $0.identityKey == currentSnapshot.identityKey })
            {
                update(account: existingCurrentAccount, from: currentSnapshot)
                if existingCurrentAccount.id == targetAccount.id {
                    desiredAuthFileContents = currentSnapshot.rawContents
                }
            }

            // Stored accounts keep a verbatim auth.json snapshot, and switching
            // should replace the whole file with that saved snapshot.
            try authFileManager.writeAuthFile(desiredAuthFileContents, promptIfNeeded: true)

            targetAccount.lastLoginAt = .now
            selection = [targetAccount.id]
            renameTargetID = nil
            activeIdentityKey = targetAccount.identityKey

            try modelContext.save()
            await notificationManager.postSwitchNotification(for: targetAccount.name)
        } catch {
            present(error, title: "Couldn't Switch Account")
        }
    }

    private func update(account: StoredAccount, from snapshot: CodexAuthSnapshot) {
        account.identityKey = snapshot.identityKey
        account.authFileContents = snapshot.rawContents
        account.authModeRaw = snapshot.authMode.rawValue
        account.emailHint = snapshot.email
        account.accountIdentifier = snapshot.accountIdentifier
    }

    private func reconcileStoredAccountsIfNeeded() {
        guard let modelContext else {
            return
        }

        do {
            var changedAccounts = false

            for account in try fetchAccounts() {
                guard let snapshot = try? CodexAuthFile.parse(contents: account.authFileContents) else {
                    continue
                }

                if account.identityKey != snapshot.identityKey
                    || account.authModeRaw != snapshot.authMode.rawValue
                    || account.emailHint != snapshot.email
                    || account.accountIdentifier != snapshot.accountIdentifier
                    || account.iconSystemName.isEmpty
                {
                    update(account: account, from: snapshot)
                    if account.iconSystemName.isEmpty {
                        account.iconSystemName = AccountIconOption.defaultOption.systemName
                    }
                    changedAccounts = true
                }
            }

            if changedAccounts {
                try modelContext.save()
            }
        } catch {
            present(error, title: "Couldn't Refresh Saved Accounts")
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
        presentedAlert = UserFacingAlert(title: title, message: message)
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
