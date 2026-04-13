//
//  StoredAccountMutations.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-12.
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
        guard account.name != trimmedName else {
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
        guard account.iconSystemName != resolvedSystemName else {
            return
        }

        account.iconSystemName = resolvedSystemName
        try modelContext.save()
    }

    @MainActor
    static func remove(
        _ account: StoredAccount,
        in modelContext: ModelContext
    ) throws {
        guard !account.isDeleted else {
            return
        }

        modelContext.delete(account)
        try modelContext.save()
    }

    @MainActor
    static func removeAll(
        _ accounts: [StoredAccount],
        in modelContext: ModelContext
    ) throws {
        let accountsToRemove = accounts.filter { !$0.isDeleted }
        guard !accountsToRemove.isEmpty else {
            return
        }

        for account in accountsToRemove {
            modelContext.delete(account)
        }

        try modelContext.save()
    }
}
