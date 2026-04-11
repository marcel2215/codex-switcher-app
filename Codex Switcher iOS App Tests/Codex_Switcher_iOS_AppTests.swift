//
//  Codex_Switcher_iOS_AppTests.swift
//  Codex Switcher iOS AppTests
//
//  Created by Codex on 2026-04-11.
//

import Foundation
import SwiftData
import Testing
@testable import Codex_Switcher_iOS_App

@MainActor
struct Codex_Switcher_iOS_AppTests {
    @Test
    func searchMatchesNameEmailHintAndAccountIdentifier() throws {
        let harness = try makeHarness(accounts: [
            makeAccount(name: "Work", emailHint: "work@example.com", accountIdentifier: "acct-work", customOrder: 0),
            makeAccount(name: "Personal", emailHint: "personal@example.com", accountIdentifier: "acct-personal", customOrder: 1),
        ])

        harness.controller.searchText = "work"
        #expect(harness.controller.displayedAccounts(from: try fetchAccounts(in: harness.modelContext)).map(\.name) == ["Work"])

        harness.controller.searchText = "personal@example.com"
        #expect(harness.controller.displayedAccounts(from: try fetchAccounts(in: harness.modelContext)).map(\.name) == ["Personal"])

        harness.controller.searchText = "acct-work"
        #expect(harness.controller.displayedAccounts(from: try fetchAccounts(in: harness.modelContext)).map(\.name) == ["Work"])
    }

    @Test
    func renameTrimsWhitespaceBeforeSaving() throws {
        let account = makeAccount(name: "Original", customOrder: 0)
        let harness = try makeHarness(accounts: [account])

        harness.controller.commitRename(for: account, proposedName: "  Updated Name  ", in: harness.modelContext)

        #expect(try fetchAccounts(in: harness.modelContext).first?.name == "Updated Name")
    }

    @Test
    func emptyRenameIsRejected() throws {
        let account = makeAccount(name: "Original", customOrder: 0)
        let harness = try makeHarness(accounts: [account])

        harness.controller.commitRename(for: account, proposedName: "   ", in: harness.modelContext)

        #expect(try fetchAccounts(in: harness.modelContext).first?.name == "Original")
    }

    @Test
    func iconChangePersists() throws {
        let account = makeAccount(name: "Work", customOrder: 0)
        let harness = try makeHarness(accounts: [account])

        harness.controller.setIcon(.terminal, for: account, in: harness.modelContext)

        #expect(try fetchAccounts(in: harness.modelContext).first?.iconSystemName == AccountIconOption.terminal.systemName)
    }

    @Test
    func customReorderUpdatesCustomOrder() throws {
        let first = makeAccount(name: "First", customOrder: 0)
        let second = makeAccount(name: "Second", customOrder: 1)
        let third = makeAccount(name: "Third", customOrder: 2)
        let harness = try makeHarness(accounts: [first, second, third])

        harness.controller.sortCriterion = .custom
        harness.controller.move(
            from: IndexSet(integer: 2),
            to: 0,
            visibleAccounts: harness.controller.displayedAccounts(from: try fetchAccounts(in: harness.modelContext)),
            in: harness.modelContext
        )

        let reordered = try fetchAccounts(in: harness.modelContext).sorted { $0.customOrder < $1.customOrder }
        #expect(reordered.map(\.name) == ["Third", "First", "Second"])
    }

    @Test
    func reorderIsDisabledWhenSearchIsActive() throws {
        let first = makeAccount(name: "First", customOrder: 0)
        let second = makeAccount(name: "Second", customOrder: 1)
        let harness = try makeHarness(accounts: [first, second])

        harness.controller.sortCriterion = .custom
        harness.controller.searchText = "first"
        harness.controller.move(
            from: IndexSet(integer: 0),
            to: 1,
            visibleAccounts: harness.controller.displayedAccounts(from: try fetchAccounts(in: harness.modelContext)),
            in: harness.modelContext
        )

        let ordered = try fetchAccounts(in: harness.modelContext).sorted { $0.customOrder < $1.customOrder }
        #expect(ordered.map(\.name) == ["First", "Second"])
    }

    @Test
    func reorderIsDisabledOutsideCustomSort() throws {
        let first = makeAccount(name: "First", customOrder: 0)
        let second = makeAccount(name: "Second", customOrder: 1)
        let harness = try makeHarness(accounts: [first, second])

        harness.controller.sortCriterion = .dateAdded
        harness.controller.move(
            from: IndexSet(integer: 0),
            to: 1,
            visibleAccounts: harness.controller.displayedAccounts(from: try fetchAccounts(in: harness.modelContext)),
            in: harness.modelContext
        )

        let ordered = try fetchAccounts(in: harness.modelContext).sorted { $0.customOrder < $1.customOrder }
        #expect(ordered.map(\.name) == ["First", "Second"])
    }

    @Test
    func deleteRemovesTheRowFromSwiftData() throws {
        let account = makeAccount(name: "Work", customOrder: 0)
        let harness = try makeHarness(accounts: [account])

        harness.controller.remove(account, in: harness.modelContext)

        #expect(try fetchAccounts(in: harness.modelContext).isEmpty)
    }

    @Test
    func restoringCustomSortForcesAscendingDirection() throws {
        let harness = try makeHarness(accounts: [])

        harness.controller.restoreSortPreferences(
            sortCriterionRawValue: AccountSortCriterion.custom.rawValue,
            sortDirectionRawValue: SortDirection.descending.rawValue
        )

        #expect(harness.controller.sortCriterion == .custom)
        #expect(harness.controller.sortDirection == .ascending)
    }
}

@MainActor
private func makeHarness(accounts: [StoredAccount]) throws -> TestHarness {
    let schema = Schema([StoredAccount.self])
    let configuration = ModelConfiguration(
        "UnitTestAccounts",
        schema: schema,
        isStoredInMemoryOnly: true,
        cloudKitDatabase: .none
    )
    let modelContainer = try ModelContainer(for: schema, configurations: [configuration])
    let modelContext = modelContainer.mainContext

    for account in accounts {
        modelContext.insert(account)
    }

    try modelContext.save()

    return TestHarness(
        modelContext: modelContext,
        controller: IOSAccountsController()
    )
}

@MainActor
private func fetchAccounts(in modelContext: ModelContext) throws -> [StoredAccount] {
    try modelContext.fetch(FetchDescriptor<StoredAccount>())
}

private func makeAccount(
    name: String,
    emailHint: String? = nil,
    accountIdentifier: String? = nil,
    customOrder: Double
) -> StoredAccount {
    StoredAccount(
        identityKey: "identity-\(UUID().uuidString)",
        name: name,
        createdAt: .now,
        customOrder: customOrder,
        authModeRaw: "chatgpt",
        emailHint: emailHint,
        accountIdentifier: accountIdentifier
    )
}

private struct TestHarness {
    let modelContext: ModelContext
    let controller: IOSAccountsController
}
