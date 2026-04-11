//
//  IOSAccountsController.swift
//  Codex Switcher iOS App
//
//  Created by Codex on 2026-04-11.
//

import Foundation
import Observation
import SwiftData
import SwiftUI

@MainActor
@Observable
final class IOSAccountsController {
    var searchText = ""
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

    func commitRename(for account: StoredAccount, proposedName: String, in modelContext: ModelContext) {
        guard !account.isDeleted else {
            return
        }

        guard let trimmedName = AccountsPresentationLogic.normalizedRenamedAccountName(proposedName) else {
            return
        }

        guard trimmedName != account.name else {
            return
        }

        do {
            account.name = trimmedName
            try modelContext.save()
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
            account.iconSystemName = resolvedSystemName
            try modelContext.save()
        } catch {
            presentedError = PresentedError(
                title: "Couldn't Change Icon",
                message: error.localizedDescription
            )
        }
    }

    func remove(_ account: StoredAccount, in modelContext: ModelContext) {
        guard !account.isDeleted else {
            return
        }

        do {
            modelContext.delete(account)
            try modelContext.save()
        } catch {
            presentedError = PresentedError(
                title: "Couldn't Remove Account",
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

        do {
            for (index, account) in reorderedAccounts.enumerated() {
                account.customOrder = Double(index)
            }

            try modelContext.save()
        } catch {
            presentedError = PresentedError(
                title: "Couldn't Reorder Accounts",
                message: error.localizedDescription
            )
        }
    }
}
