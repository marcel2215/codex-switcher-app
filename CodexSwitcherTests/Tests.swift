//
//  Tests.swift
//  Codex Switcher Tests
//
//  Created by Marcel Kwiatkowski on 2026-04-11.
//

import Foundation
import SwiftData
import Testing
import UIKit
@testable import Codex_Switcher

@MainActor
struct Tests {
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
    func deleteRemovesTheRowFromSwiftData() async throws {
        let account = makeAccount(name: "Work", customOrder: 0)
        let harness = try makeHarness(accounts: [account])

        await harness.controller.remove(account, in: harness.modelContext)

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
    func archiveTransferItemKeepsStableIdentityAcrossRenders() async throws {
        let snapshotContents = makeChatGPTAuthJSON(accountID: "acct-stable-share")
        let snapshot = try SharedCodexAuthFile.parse(contents: snapshotContents)
        let snapshotStore = FakeSnapshotStore()
        let accountID = UUID()
        let account = StoredAccount(
            id: accountID,
            identityKey: snapshot.identityKey,
            name: "Stable Share",
            customOrder: 0,
            authModeRaw: snapshot.authMode.rawValue,
            emailHint: snapshot.email,
            accountIdentifier: snapshot.accountIdentifier
        )
        let harness = try makeHarness(accounts: [account], snapshotStore: snapshotStore)
        let unavailableItem = harness.controller.archiveTransferItem(for: account)

        try await snapshotStore.saveSnapshot(snapshotContents, forIdentityKey: snapshot.identityKey)

        let firstItem = harness.controller.archiveTransferItem(for: account)
        let secondItem = harness.controller.archiveTransferItem(for: account)

        #expect(firstItem.id == accountID)
        #expect(secondItem.id == accountID)
        #expect(firstItem.availabilityKey == secondItem.availabilityKey)
        #expect(unavailableItem.availabilityKey != firstItem.availabilityKey)
        #expect(unavailableItem.request.exportContentKey == firstItem.request.exportContentKey)
    }

    @Test
    func preparedArchiveFileExportsFileBeforeSharing() async throws {
        let snapshotContents = makeChatGPTAuthJSON(accountID: "acct-prepared-share")
        let snapshot = try SharedCodexAuthFile.parse(contents: snapshotContents)
        let snapshotStore = FakeSnapshotStore()
        let account = StoredAccount(
            identityKey: snapshot.identityKey,
            name: "Prepared Share",
            customOrder: 0,
            authModeRaw: snapshot.authMode.rawValue,
            emailHint: snapshot.email,
            accountIdentifier: snapshot.accountIdentifier
        )
        let harness = try makeHarness(accounts: [account], snapshotStore: snapshotStore)

        try await snapshotStore.saveSnapshot(snapshotContents, forIdentityKey: snapshot.identityKey)

        let preparedFile = try await harness.controller.prepareArchiveFile(for: account)
        defer { try? FileManager.default.removeItem(at: preparedFile.fileURL.deletingLastPathComponent()) }

        #expect(FileManager.default.fileExists(atPath: preparedFile.fileURL.path))
        #expect(preparedFile.fileURL.lastPathComponent == "Prepared Share.cxa")
        #expect(preparedFile.suggestedFilename == "Prepared Share.cxa")

        let archive = try CodexAccountArchive.decode(from: Data(contentsOf: preparedFile.fileURL))
        let archivedAccount = try #require(archive.accounts.first)
        #expect(archivedAccount.snapshotContents == snapshotContents)
        #expect(archivedAccount.identityKey == snapshot.identityKey)
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
        #expect(harness.controller.archiveTransferItem(for: existingAccount).request.accounts.first?.hasLocalSnapshot == false)
        #expect(await harness.controller.canExportArchive(for: existingAccount) == false)

        let importedAccountIDs = await harness.controller.importAccountArchives(
            from: [archiveURL],
            in: harness.modelContext
        )

        #expect(importedAccountIDs == [existingAccount.id])
        #expect(harness.controller.archiveTransferItem(for: existingAccount).request.accounts.first?.hasLocalSnapshot == true)
        #expect(await harness.controller.canExportArchive(for: existingAccount))
        #expect(await snapshotStore.saveCallCount() == 1)
        #expect(await snapshotStore.snapshot(forIdentityKey: snapshot.identityKey) == snapshotContents)
        #expect(harness.controller.archiveAvailabilityRefreshToken == 1)
    }

    @Test
    func importingArchiveDoesNotPersistBrokenAccountWhenSnapshotWriteFails() async throws {
        let snapshotContents = makeChatGPTAuthJSON(accountID: "acct-import-failure")
        let snapshot = try SharedCodexAuthFile.parse(contents: snapshotContents)
        let snapshotStore = FakeSnapshotStore()
        snapshotStore.setSaveError(FakeStoreError.simulatedFailure)
        let harness = try makeHarness(accounts: [], snapshotStore: snapshotStore)
        let archiveURL = try makeArchiveFile(
            archive: CodexAccountArchive(
                name: "Broken Import",
                iconSystemName: AccountIconOption.defaultOption.systemName,
                identityKey: snapshot.identityKey,
                authModeRaw: snapshot.authMode.rawValue,
                emailHint: snapshot.email,
                accountIdentifier: snapshot.accountIdentifier,
                snapshotContents: snapshotContents
            )
        )
        defer { try? FileManager.default.removeItem(at: archiveURL.deletingLastPathComponent()) }

        let importedAccountIDs = await harness.controller.importAccountArchives(
            from: [archiveURL],
            in: harness.modelContext
        )

        #expect(importedAccountIDs.isEmpty)
        #expect(try fetchAccounts(in: harness.modelContext).isEmpty)
    }

    @Test
    func importingMultiAccountArchiveImportsEveryAccount() async throws {
        let firstSnapshotContents = makeChatGPTAuthJSON(accountID: "acct-multi-1")
        let secondSnapshotContents = makeChatGPTAuthJSON(accountID: "acct-multi-2")
        let firstSnapshot = try SharedCodexAuthFile.parse(contents: firstSnapshotContents)
        let secondSnapshot = try SharedCodexAuthFile.parse(contents: secondSnapshotContents)
        let snapshotStore = FakeSnapshotStore()
        let harness = try makeHarness(accounts: [], snapshotStore: snapshotStore)
        let archiveURL = try makeArchiveFile(
            archive: CodexAccountArchive(
                accounts: [
                    CodexAccountArchive.Account(
                        name: "First",
                        iconSystemName: AccountIconOption.briefcase.systemName,
                        identityKey: firstSnapshot.identityKey,
                        authModeRaw: firstSnapshot.authMode.rawValue,
                        emailHint: firstSnapshot.email,
                        accountIdentifier: firstSnapshot.accountIdentifier,
                        snapshotContents: firstSnapshotContents
                    ),
                    CodexAccountArchive.Account(
                        name: "Second",
                        iconSystemName: AccountIconOption.house.systemName,
                        identityKey: secondSnapshot.identityKey,
                        authModeRaw: secondSnapshot.authMode.rawValue,
                        emailHint: secondSnapshot.email,
                        accountIdentifier: secondSnapshot.accountIdentifier,
                        snapshotContents: secondSnapshotContents
                    ),
                ]
            )
        )
        defer { try? FileManager.default.removeItem(at: archiveURL.deletingLastPathComponent()) }

        let importedAccountIDs = await harness.controller.importAccountArchives(
            from: [archiveURL],
            in: harness.modelContext
        )

        let accounts = try fetchAccounts(in: harness.modelContext)
        #expect(importedAccountIDs.count == 2)
        #expect(accounts.count == 2)
        #expect(Set(accounts.map(\.identityKey)) == Set([firstSnapshot.identityKey, secondSnapshot.identityKey]))
        #expect(await snapshotStore.snapshot(forIdentityKey: firstSnapshot.identityKey) == firstSnapshotContents)
        #expect(await snapshotStore.snapshot(forIdentityKey: secondSnapshot.identityKey) == secondSnapshotContents)
    }

    @Test
    func importingArchiveExportsSyncedRateLimitCredential() async throws {
        let snapshotContents = makeChatGPTAuthJSON(accountID: "acct-credential-export")
        let snapshot = try SharedCodexAuthFile.parse(contents: snapshotContents)
        let syncedCredentialStore = FakeSyncedRateLimitCredentialStore()
        let harness = try makeHarness(
            accounts: [],
            syncedRateLimitCredentialStore: syncedCredentialStore
        )
        let archiveURL = try makeArchiveFile(
            archive: CodexAccountArchive(
                name: "Credential Export",
                iconSystemName: AccountIconOption.defaultOption.systemName,
                identityKey: snapshot.identityKey,
                authModeRaw: snapshot.authMode.rawValue,
                emailHint: snapshot.email,
                accountIdentifier: snapshot.accountIdentifier,
                snapshotContents: snapshotContents
            )
        )
        defer { try? FileManager.default.removeItem(at: archiveURL.deletingLastPathComponent()) }

        let importedAccountIDs = await harness.controller.importAccountArchives(
            from: [archiveURL],
            in: harness.modelContext
        )

        #expect(importedAccountIDs.count == 1)
        #expect(await syncedCredentialStore.containsCredential(forIdentityKey: snapshot.identityKey))
    }

    @Test
    func deletingAccountRemovesSnapshotAndSyncedCredentialWhenLastIdentityIsDeleted() async throws {
        let snapshotContents = makeChatGPTAuthJSON(accountID: "acct-delete-cleanup")
        let snapshot = try SharedCodexAuthFile.parse(contents: snapshotContents)
        let snapshotStore = FakeSnapshotStore()
        let syncedCredentialStore = FakeSyncedRateLimitCredentialStore()
        let account = StoredAccount(
            identityKey: snapshot.identityKey,
            name: "Delete Me",
            customOrder: 0,
            authModeRaw: snapshot.authMode.rawValue,
            emailHint: snapshot.email,
            accountIdentifier: snapshot.accountIdentifier
        )
        let harness = try makeHarness(
            accounts: [account],
            snapshotStore: snapshotStore,
            syncedRateLimitCredentialStore: syncedCredentialStore
        )

        try await snapshotStore.saveSnapshot(snapshotContents, forIdentityKey: snapshot.identityKey)
        let rateLimitCredentials = try SharedCodexAuthFile.parseRateLimitCredentials(contents: snapshotContents)
        try await syncedCredentialStore.save(SyncedRateLimitCredential(credentials: rateLimitCredentials))

        await harness.controller.remove(account, in: harness.modelContext)

        #expect(try fetchAccounts(in: harness.modelContext).isEmpty)
        #expect(await snapshotStore.snapshot(forIdentityKey: snapshot.identityKey) == nil)
        #expect(await syncedCredentialStore.containsCredential(forIdentityKey: snapshot.identityKey) == false)
    }

    @Test
    func sharedCloudSyncRepairMigratesLegacyAuthFileContents() async throws {
        let snapshotContents = makeChatGPTAuthJSON(accountID: "acct-legacy-repair")
        let snapshot = try SharedCodexAuthFile.parse(contents: snapshotContents)
        let snapshotStore = FakeSnapshotStore()
        let syncedCredentialStore = FakeSyncedRateLimitCredentialStore()
        let account = StoredAccount(
            identityKey: "legacy-placeholder",
            name: "",
            customOrder: 0,
            authFileContents: snapshotContents,
            hasLocalSnapshot: true,
            authModeRaw: "chatgpt"
        )
        let harness = try makeHarness(
            accounts: [account],
            snapshotStore: snapshotStore,
            syncedRateLimitCredentialStore: syncedCredentialStore
        )

        let didChange = try await StoredAccountLegacyCloudSyncRepair.run(
            in: harness.modelContext,
            snapshotStore: snapshotStore,
            syncedRateLimitCredentialStore: syncedCredentialStore
        )

        let repairedAccount = try #require(fetchAccounts(in: harness.modelContext).first)
        #expect(didChange)
        #expect(repairedAccount.identityKey == snapshot.identityKey)
        #expect(repairedAccount.authFileContents == nil)
        #expect(repairedAccount.hasLocalSnapshot == false)
        #expect(await snapshotStore.snapshot(forIdentityKey: snapshot.identityKey) == snapshotContents)
        #expect(await syncedCredentialStore.containsCredential(forIdentityKey: snapshot.identityKey))
    }

    @Test
    func sharedCloudSyncRepairMovesCurrentSnapshotToRepairedIdentityKeyAndExportsCredential() async throws {
        let snapshotContents = makeChatGPTAuthJSON(accountID: "acct-current-repair")
        let snapshot = try SharedCodexAuthFile.parse(contents: snapshotContents)
        let legacyIdentityKey = "legacy-identity"
        let snapshotStore = FakeSnapshotStore()
        let syncedCredentialStore = FakeSyncedRateLimitCredentialStore()
        let account = StoredAccount(
            identityKey: legacyIdentityKey,
            name: "Legacy",
            customOrder: 0,
            authModeRaw: snapshot.authMode.rawValue
        )
        let harness = try makeHarness(
            accounts: [account],
            snapshotStore: snapshotStore,
            syncedRateLimitCredentialStore: syncedCredentialStore
        )

        try await snapshotStore.saveSnapshot(snapshotContents, forIdentityKey: legacyIdentityKey)

        let didChange = try await StoredAccountLegacyCloudSyncRepair.run(
            in: harness.modelContext,
            snapshotStore: snapshotStore,
            syncedRateLimitCredentialStore: syncedCredentialStore
        )

        let repairedAccount = try #require(fetchAccounts(in: harness.modelContext).first)
        #expect(didChange)
        #expect(repairedAccount.identityKey == snapshot.identityKey)
        #expect(await snapshotStore.snapshot(forIdentityKey: legacyIdentityKey) == nil)
        #expect(await snapshotStore.snapshot(forIdentityKey: snapshot.identityKey) == snapshotContents)
        #expect(await syncedCredentialStore.containsCredential(forIdentityKey: snapshot.identityKey))
    }

    @Test
    func duplicateMergePreservesPinnedStateAndMetricStatuses() async throws {
        let identityKey = "chatgpt:duplicate-shared"
        let survivor = StoredAccount(
            identityKey: identityKey,
            name: "Account 1",
            createdAt: .distantPast,
            customOrder: 10,
            isPinned: false,
            authModeRaw: CodexAuthMode.chatgpt.rawValue,
            sevenDayDataStatusRaw: RateLimitMetricDataStatus.missing.rawValue,
            fiveHourDataStatusRaw: RateLimitMetricDataStatus.missing.rawValue
        )
        let duplicate = StoredAccount(
            identityKey: identityKey,
            name: "Work",
            createdAt: .now,
            customOrder: 0,
            isPinned: true,
            authModeRaw: CodexAuthMode.chatgpt.rawValue,
            sevenDayLimitUsedPercent: 12,
            fiveHourLimitUsedPercent: 34,
            sevenDayDataStatusRaw: RateLimitMetricDataStatus.exact.rawValue,
            fiveHourDataStatusRaw: RateLimitMetricDataStatus.cached.rawValue,
            rateLimitsObservedAt: .now
        )
        let harness = try makeHarness(accounts: [survivor, duplicate])

        let didChange = try await StoredAccountLegacyCloudSyncRepair.run(in: harness.modelContext)

        let accounts = try fetchAccounts(in: harness.modelContext)
        let mergedAccount = try #require(accounts.first)
        #expect(didChange)
        #expect(accounts.count == 1)
        #expect(mergedAccount.isPinned)
        #expect(mergedAccount.name == "Work")
        #expect(mergedAccount.sevenDayDataStatusRaw == RateLimitMetricDataStatus.exact.rawValue)
        #expect(mergedAccount.fiveHourDataStatusRaw == RateLimitMetricDataStatus.cached.rawValue)
    }

    @Test
    func widgetSnapshotFallbackRequiresExplicitStartupAllowance() {
        let existingState = SharedCodexState(
            schemaVersion: SharedCodexState.currentSchemaVersion,
            authState: .ready,
            linkedFolderPath: nil,
            currentAccountID: nil,
            selectedAccountID: nil,
            selectedAccountIsLive: false,
            accounts: [
                SharedCodexAccountRecord(
                    id: "identity-fallback",
                    name: "Fallback",
                    iconSystemName: AccountIconOption.defaultOption.systemName,
                    emailHint: nil,
                    accountIdentifier: nil,
                    authModeRaw: CodexAuthMode.chatgpt.rawValue,
                    lastLoginAt: nil,
                    sevenDayLimitUsedPercent: nil,
                    fiveHourLimitUsedPercent: nil,
                    sevenDayResetsAt: nil,
                    fiveHourResetsAt: nil,
                    sevenDayDataStatusRaw: RateLimitMetricDataStatus.missing.rawValue,
                    fiveHourDataStatusRaw: RateLimitMetricDataStatus.missing.rawValue,
                    rateLimitsObservedAt: nil,
                    sortOrder: 0,
                    isPinned: false,
                    hasLocalSnapshot: true
                )
            ],
            updatedAt: .now
        )

        #expect(
            WidgetSnapshotPublisher.mergedAccounts(
                localAccounts: [],
                existingState: existingState,
                allowEmptyStoreFallback: false
            ).isEmpty
        )
        #expect(
            WidgetSnapshotPublisher.mergedAccounts(
                localAccounts: [],
                existingState: existingState,
                allowEmptyStoreFallback: true
            ) == existingState.accounts
        )
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
    snapshotStore: FakeSnapshotStore = FakeSnapshotStore(),
    syncedRateLimitCredentialStore: FakeSyncedRateLimitCredentialStore = FakeSyncedRateLimitCredentialStore()
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

    let snapshotAvailabilityStore = LocalAccountSnapshotAvailabilityStore(
        baseURL: FileManager.default.temporaryDirectory.appendingPathComponent(
            "CodexSwitcherIOSTests-\(UUID().uuidString)",
            isDirectory: true
        )
    )
    snapshotStore.attachSnapshotAvailabilityStore(snapshotAvailabilityStore)

    return TestHarness(
        modelContainer: modelContainer,
        modelContext: modelContext,
        controller: IOSAccountsController(
            snapshotStore: snapshotStore,
            archiveExporter: CodexAccountArchiveFileExporter(snapshotStore: snapshotStore),
            syncedRateLimitCredentialStore: syncedRateLimitCredentialStore,
            snapshotAvailabilityStore: snapshotAvailabilityStore
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
    private var snapshotAvailabilityStore: LocalAccountSnapshotAvailabilityStore?
    private var snapshots: [String: String] = [:]
    private var legacySnapshots: [UUID: String] = [:]
    private var saveCount = 0
    private var saveError: Error?
    private var loadError: Error?
    private var deleteError: Error?

    init(snapshotAvailabilityStore: LocalAccountSnapshotAvailabilityStore? = nil) {
        self.snapshotAvailabilityStore = snapshotAvailabilityStore
    }

    func attachSnapshotAvailabilityStore(_ snapshotAvailabilityStore: LocalAccountSnapshotAvailabilityStore) {
        self.snapshotAvailabilityStore = snapshotAvailabilityStore
    }

    func saveSnapshot(_ contents: String, forIdentityKey identityKey: String) async throws {
        try withLock {
            if let saveError {
                throw saveError
            }

            snapshots[identityKey] = contents
            saveCount += 1
        }
        snapshotAvailabilityStore?.setSnapshotAvailable(true, forIdentityKey: identityKey)
    }

    func loadSnapshot(forIdentityKey identityKey: String) async throws -> String {
        let snapshot = try withLock {
            if let loadError {
                throw loadError
            }

            return snapshots[identityKey]
        }
        guard let snapshot else {
            throw AccountSnapshotStoreError.missingSnapshot
        }

        return snapshot
    }

    func deleteSnapshot(forIdentityKey identityKey: String) async throws {
        try withLock {
            if let deleteError {
                throw deleteError
            }

            snapshots.removeValue(forKey: identityKey)
        }
        snapshotAvailabilityStore?.setSnapshotAvailable(false, forIdentityKey: identityKey)
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
        let didMigrate = try withLock {
            if let saveError {
                throw saveError
            }

            guard snapshots[identityKey] == nil, let legacySnapshot = legacySnapshots.removeValue(forKey: accountID) else {
                legacySnapshots.removeValue(forKey: accountID)
                return false
            }

            snapshots[identityKey] = legacySnapshot
            saveCount += 1
            return true
        }

        if didMigrate {
            snapshotAvailabilityStore?.setSnapshotAvailable(true, forIdentityKey: identityKey)
        }

        return didMigrate
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

    func setSaveError(_ error: Error?) {
        withLock {
            saveError = error
        }
    }

    func setLoadError(_ error: Error?) {
        withLock {
            loadError = error
        }
    }

    func setDeleteError(_ error: Error?) {
        withLock {
            deleteError = error
        }
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

actor FakeSyncedRateLimitCredentialStore: SyncedRateLimitCredentialStoring {
    private var credentials: [String: SyncedRateLimitCredential] = [:]

    func save(_ credential: SyncedRateLimitCredential) async throws {
        credentials[credential.identityKey] = credential
    }

    func load(forIdentityKey identityKey: String) async throws -> SyncedRateLimitCredential {
        guard let credential = credentials[identityKey] else {
            throw SyncedRateLimitCredentialStoreError.missingCredential
        }

        return credential
    }

    func delete(forIdentityKey identityKey: String) async throws {
        credentials.removeValue(forKey: identityKey)
    }

    func containsCredential(forIdentityKey identityKey: String) async -> Bool {
        credentials[identityKey] != nil
    }
}

private enum FakeStoreError: Error {
    case simulatedFailure
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
