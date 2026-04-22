//
//  CodexSwitcheriOSAppTests.swift
//  Codex Switcher iOS AppTests
//
//  Created by Codex on 2026-04-11.
//

import Foundation
import SwiftData
import Testing
import UIKit
@testable import CodexSwitcher_iOS_App

@MainActor
struct CodexSwitcheriOSAppTests {
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
    func emptyRenameClearsStoredName() throws {
        let account = makeAccount(name: "Original", customOrder: 0)
        let harness = try makeHarness(accounts: [account])

        harness.controller.commitRename(for: account, proposedName: "   ", in: harness.modelContext)

        #expect(try fetchAccounts(in: harness.modelContext).first?.name == "")
    }

    @Test
    func displayNameFallsBackToEmailHintWhenNameIsEmpty() {
        let account = makeAccount(
            name: "",
            emailHint: "work@example.com",
            accountIdentifier: "acct-work",
            customOrder: 0
        )

        #expect(AccountsPresentationLogic.displayName(for: account) == "work@example.com")
    }

    @Test
    func iconChangePersists() throws {
        let account = makeAccount(name: "Work", customOrder: 0)
        let harness = try makeHarness(accounts: [account])

        harness.controller.setIcon(.terminal, for: account, in: harness.modelContext)

        #expect(try fetchAccounts(in: harness.modelContext).first?.iconSystemName == AccountIconOption.terminal.systemName)
    }

    @Test
    func pinChangePersistsAndKeepsPinnedAccountsFirst() throws {
        let first = makeAccount(name: "First", customOrder: 0)
        let second = makeAccount(name: "Second", customOrder: 1)
        let harness = try makeHarness(accounts: [first, second])

        harness.controller.sortCriterion = .custom
        harness.controller.setPinned(true, for: second, in: harness.modelContext)

        let refreshedAccounts = try fetchAccounts(in: harness.modelContext)
        let refreshedSecond = try #require(refreshedAccounts.first(where: { $0.id == second.id }))

        #expect(refreshedSecond.isPinned)
        #expect(harness.controller.displayedAccounts(from: refreshedAccounts).map(\.name) == ["Second", "First"])
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
    func customReorderPreservesPinnedBoundary() throws {
        let pinned = makeAccount(name: "Pinned", customOrder: 0, isPinned: true)
        let first = makeAccount(name: "First", customOrder: 1)
        let second = makeAccount(name: "Second", customOrder: 2)
        let harness = try makeHarness(accounts: [pinned, first, second])

        harness.controller.sortCriterion = .custom
        harness.controller.move(
            from: IndexSet(integer: 2),
            to: 0,
            visibleAccounts: harness.controller.displayedAccounts(from: try fetchAccounts(in: harness.modelContext)),
            in: harness.modelContext
        )

        let ordered = try fetchAccounts(in: harness.modelContext)
            .sorted { $0.customOrder < $1.customOrder }
        #expect(ordered.map(\.name) == ["Pinned", "Second", "First"])
        #expect(harness.controller.displayedAccounts(from: ordered).map(\.name) == ["Pinned", "Second", "First"])
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
    func removingAccountReturnsCompactNavigationToHomeEvenWithoutSelection() {
        let accountID = UUID()

        #expect(
            AccountsRootView.shouldReturnToAccountsHome(
                afterRemovingAccountWithID: accountID,
                usesCompactNavigation: true,
                selectedAccountID: nil
            )
        )
    }

    @Test
    func removingSelectedAccountReturnsRegularNavigationToHome() {
        let accountID = UUID()

        #expect(
            AccountsRootView.shouldReturnToAccountsHome(
                afterRemovingAccountWithID: accountID,
                usesCompactNavigation: false,
                selectedAccountID: accountID
            )
        )
        #expect(
            AccountsRootView.shouldReturnToAccountsHome(
                afterRemovingAccountWithID: accountID,
                usesCompactNavigation: false,
                selectedAccountID: UUID()
            ) == false
        )
    }

    @Test
    func importingUnchangedArchiveForExistingAccountStillSucceeds() async throws {
        let snapshotContents = makeChatGPTAuthJSON(accountID: "acct-import")
        let snapshot = try SharedCodexAuthFile.parse(contents: snapshotContents)
        let snapshotStore = FakeSnapshotStore()
        let existingAccount = StoredAccount(
            identityKey: snapshot.identityKey,
            name: snapshot.email ?? "Imported Account",
            customOrder: 0,
            hasLocalSnapshot: true,
            authModeRaw: snapshot.authMode.rawValue,
            emailHint: snapshot.email,
            accountIdentifier: snapshot.accountIdentifier
        )
        let harness = try makeHarness(accounts: [existingAccount], snapshotStore: snapshotStore)
        let archiveURL = try makeArchiveFile(
            archive: CodexAccountArchive(
                name: existingAccount.name,
                iconSystemName: existingAccount.iconSystemName,
                identityKey: snapshot.identityKey,
                authModeRaw: snapshot.authMode.rawValue,
                emailHint: snapshot.email,
                accountIdentifier: snapshot.accountIdentifier,
                snapshotContents: snapshotContents
            )
        )

        try await snapshotStore.saveSnapshot(snapshotContents, forIdentityKey: snapshot.identityKey)
        snapshotStore.resetSaveCallCount()
        defer { try? FileManager.default.removeItem(at: archiveURL.deletingLastPathComponent()) }

        let importedAccountIDs = await harness.controller.importAccountArchives(
            from: [archiveURL],
            in: harness.modelContext
        )

        #expect(importedAccountIDs == [existingAccount.id])
        #expect(try fetchAccounts(in: harness.modelContext).count == 1)
        #expect(await snapshotStore.saveCallCount() == 0)
        #expect(await snapshotStore.snapshot(forIdentityKey: snapshot.identityKey) == snapshotContents)
    }

    @Test
    func importingArchiveRepairsMissingSnapshotAndRefreshesExportAvailability() async throws {
        let snapshotContents = makeChatGPTAuthJSON(accountID: "acct-repair")
        let snapshot = try SharedCodexAuthFile.parse(contents: snapshotContents)
        let snapshotStore = FakeSnapshotStore()
        let existingAccount = StoredAccount(
            identityKey: snapshot.identityKey,
            name: snapshot.email ?? "Imported Account",
            customOrder: 0,
            hasLocalSnapshot: true,
            authModeRaw: snapshot.authMode.rawValue,
            emailHint: snapshot.email,
            accountIdentifier: snapshot.accountIdentifier
        )
        let harness = try makeHarness(accounts: [existingAccount], snapshotStore: snapshotStore)
        let archiveURL = try makeArchiveFile(
            archive: CodexAccountArchive(
                name: existingAccount.name,
                iconSystemName: existingAccount.iconSystemName,
                identityKey: snapshot.identityKey,
                authModeRaw: snapshot.authMode.rawValue,
                emailHint: snapshot.email,
                accountIdentifier: snapshot.accountIdentifier,
                snapshotContents: snapshotContents
            )
        )
        defer { try? FileManager.default.removeItem(at: archiveURL.deletingLastPathComponent()) }

        #expect(harness.controller.archiveAvailabilityRefreshToken == 0)
        #expect(await harness.controller.canExportArchive(for: existingAccount) == false)

        let importedAccountIDs = await harness.controller.importAccountArchives(
            from: [archiveURL],
            in: harness.modelContext
        )

        #expect(importedAccountIDs == [existingAccount.id])
        #expect(await harness.controller.canExportArchive(for: existingAccount))
        #expect(await snapshotStore.saveCallCount() == 1)
        #expect(await snapshotStore.snapshot(forIdentityKey: snapshot.identityKey) == snapshotContents)
        #expect(harness.controller.archiveAvailabilityRefreshToken == 1)
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

    @Test
    func homeScreenQuickActionAccountsUseAppOrderAndLimitToFour() throws {
        let harness = try makeHarness(accounts: [
            makeAccount(name: "Delta", customOrder: 0),
            makeAccount(name: "Bravo", customOrder: 1, iconSystemName: AccountIconOption.briefcase.systemName),
            makeAccount(name: "Echo", customOrder: 2, iconSystemName: AccountIconOption.house.systemName),
            makeAccount(name: "Alpha", emailHint: "alpha@example.com", customOrder: 3),
            makeAccount(name: "Charlie", accountIdentifier: "acct-charlie", customOrder: 4),
        ])

        harness.controller.sortCriterion = AccountSortCriterion.name
        harness.controller.sortDirection = SortDirection.ascending

        let quickActionAccounts = harness.controller.homeScreenQuickActionAccounts(
            from: try fetchAccounts(in: harness.modelContext),
            limit: 4
        )
        let quickActionTitles = quickActionAccounts.map(\.title)
        let quickActionSubtitles = quickActionAccounts.map(\.subtitle)
        let quickActionIcons = quickActionAccounts.map(\.iconSystemName)

        #expect(quickActionAccounts.count == 4)
        #expect(quickActionTitles == ["Alpha", "Bravo", "Charlie", "Delta"])
        #expect(quickActionSubtitles == [nil, nil, nil, nil])
        #expect(quickActionIcons == [
            AccountIconOption.defaultOption.systemName,
            AccountIconOption.briefcase.systemName,
            AccountIconOption.defaultOption.systemName,
            AccountIconOption.defaultOption.systemName,
        ])
    }

    @Test
    func homeScreenQuickActionCoordinatorBuildsAndQueuesAccountDetailShortcut() {
        let coordinator = IOSHomeScreenQuickActionCoordinator()
        let accountID = UUID()
        let shortcutItem = coordinator.shortcutItems(
            from: [
                IOSHomeScreenQuickActionAccountItem(
                    id: accountID,
                    title: "Work",
                    subtitle: nil,
                    iconSystemName: AccountIconOption.briefcase.systemName
                )
            ]
        )[0]

        #expect(shortcutItem.localizedTitle == "Work")
        #expect(shortcutItem.localizedSubtitle == nil)
        #expect(coordinator.handleShortcutItem(shortcutItem))
        #expect(coordinator.pendingAccountDetailID == accountID)

        coordinator.clearPendingAccountDetailID(ifMatching: accountID)

        #expect(coordinator.pendingAccountDetailID == nil)
    }
}

@MainActor
private func makeHarness(
    accounts: [StoredAccount],
    snapshotStore: FakeSnapshotStore = FakeSnapshotStore()
) throws -> TestHarness {
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
        modelContainer: modelContainer,
        modelContext: modelContext,
        controller: IOSAccountsController(
            snapshotStore: snapshotStore,
            archiveExporter: CodexAccountArchiveFileExporter(snapshotStore: snapshotStore)
        )
    )
}

@MainActor
private func fetchAccounts(in modelContext: ModelContext) throws -> [StoredAccount] {
    try modelContext.fetch(FetchDescriptor<StoredAccount>())
}

@MainActor
private func makeAccount(
    name: String,
    emailHint: String? = nil,
    accountIdentifier: String? = nil,
    customOrder: Double,
    isPinned: Bool = false,
    iconSystemName: String = AccountIconOption.defaultOption.systemName
) -> StoredAccount {
    StoredAccount(
        identityKey: "identity-\(UUID().uuidString)",
        name: name,
        createdAt: .now,
        customOrder: customOrder,
        isPinned: isPinned,
        authModeRaw: "chatgpt",
        emailHint: emailHint,
        accountIdentifier: accountIdentifier,
        iconSystemName: iconSystemName
    )
}

private struct TestHarness {
    let modelContainer: ModelContainer
    let modelContext: ModelContext
    let controller: IOSAccountsController
}

final class FakeSnapshotStore: @unchecked Sendable, AccountSnapshotStoring {
    private let lock = NSLock()
    private var snapshots: [String: String] = [:]
    private var legacySnapshots: [UUID: String] = [:]
    private var saveCount = 0

    func saveSnapshot(_ contents: String, forIdentityKey identityKey: String) async throws {
        withLock {
            snapshots[identityKey] = contents
            saveCount += 1
        }
    }

    func loadSnapshot(forIdentityKey identityKey: String) async throws -> String {
        let snapshot = withLock {
            snapshots[identityKey]
        }
        guard let snapshot else {
            throw AccountSnapshotStoreError.missingSnapshot
        }

        return snapshot
    }

    func deleteSnapshot(forIdentityKey identityKey: String) async throws {
        _ = withLock {
            snapshots.removeValue(forKey: identityKey)
        }
    }

    func containsSnapshot(forIdentityKey identityKey: String) async -> Bool {
        withLock {
            snapshots[identityKey] != nil
        }
    }

    func migrateLegacySnapshotIfNeeded(
        fromLegacyAccountID accountID: UUID,
        toIdentityKey identityKey: String
    ) async throws -> Bool {
        withLock {
            guard snapshots[identityKey] == nil, let legacySnapshot = legacySnapshots.removeValue(forKey: accountID) else {
                legacySnapshots.removeValue(forKey: accountID)
                return false
            }

            snapshots[identityKey] = legacySnapshot
            saveCount += 1
            return true
        }
    }

    func snapshot(forIdentityKey identityKey: String) async -> String? {
        withLock {
            snapshots[identityKey]
        }
    }

    func saveCallCount() async -> Int {
        withLock {
            saveCount
        }
    }

    func resetSaveCallCount() {
        withLock {
            saveCount = 0
        }
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

private func makeArchiveFile(archive: CodexAccountArchive) throws -> URL {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("CodexSwitcherIOSArchiveTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

    let fileURL = directoryURL.appendingPathComponent("archive.cxa", isDirectory: false)
    try archive.encodedData().write(to: fileURL, options: .atomic)
    return fileURL
}

private func makeChatGPTAuthJSON(
    accountID: String,
    userID: String? = nil,
    subject: String? = nil,
    email: String? = nil
) -> String {
    let authClaims: [String: Any] = [
        "chatgpt_account_id": accountID,
        "chatgpt_user_id": userID ?? "user-\(accountID)",
    ]

    var idTokenPayload: [String: Any] = [
        "email": email ?? "\(accountID)@example.com",
        "https://api.openai.com/auth": authClaims,
    ]
    if let subject {
        idTokenPayload["sub"] = subject
    }

    var accessTokenPayload: [String: Any] = [
        "https://api.openai.com/auth": authClaims,
    ]
    if let subject {
        accessTokenPayload["sub"] = subject
    }

    return """
    {
      "auth_mode": "chatgpt",
      "tokens": {
        "account_id": "\(accountID)",
        "id_token": "\(makeJWT(idTokenPayload))",
        "access_token": "\(makeJWT(accessTokenPayload))",
        "refresh_token": "refresh-\(accountID)"
      }
    }
    """
}

private func makeJWT(_ payload: [String: Any]) -> String {
    let header = ["alg": "none", "typ": "JWT"]
    let headerData = try! JSONSerialization.data(withJSONObject: header, options: [.sortedKeys])
    let payloadData = try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])

    func encode(_ data: Data) -> String {
        data
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    return "\(encode(headerData)).\(encode(payloadData)).c2ln"
}
