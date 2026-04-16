//
//  CodexSwitcherTests.swift
//  Codex SwitcherTests
//
//  Created by Marcel Kwiatkowski on 2026-04-06.
//

import AppKit
import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import Codex_Switcher

@Suite(.serialized)
@MainActor
struct CodexSwitcherTests {
    @Test func pendingAccountOpenRequestRoundTripsAndConsumesOnce() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let store = CodexPendingAccountOpenRequestStore(baseURL: temporaryDirectory)

        try store.save(identityKey: "chatgpt:auth0|acct/with spaces+symbols")

        let firstRead = try #require(try store.consume())
        #expect(firstRead.identityKey == "chatgpt:auth0|acct/with spaces+symbols")
        let secondRead = try store.consume()
        #expect(secondRead == nil)
    }

    @Test func pendingAccountOpenRequestRejectsBlankIdentityKeys() {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = CodexPendingAccountOpenRequestStore(baseURL: temporaryDirectory)

        #expect(throws: CodexPendingAccountOpenRequestError.missingIdentityKey) {
            try store.save(identityKey: "   ")
        }
    }

    @Test func parsesChatGPTAuthFile() throws {
        let rawContents = makeChatGPTAuthJSON(
            accountID: "acct-123",
            userID: "user-123",
            subject: "auth0|acct-123",
            email: "tester@example.com"
        )

        let snapshot = try CodexAuthFile.parse(contents: rawContents)

        #expect(snapshot.authMode == .chatgpt)
        #expect(snapshot.identityKey.hasPrefix("chatgpt:"))
        #expect(snapshot.accountIdentifier == "acct-123")
        #expect(snapshot.email == "tester@example.com")
    }

    @Test func parsesAPIKeyAuthFileWithoutHardcodingUsernames() throws {
        let rawContents = """
        {
          "auth_mode": "apiKey",
          "OPENAI_API_KEY": "sk-test-123"
        }
        """

        let snapshot = try CodexAuthFile.parse(contents: rawContents)

        #expect(snapshot.authMode == .apiKey)
        #expect(snapshot.identityKey.hasPrefix("api-key:"))
        #expect(snapshot.accountIdentifier == nil)
    }

    @Test func parsesRateLimitCredentialsFromChatGPTAuthFile() throws {
        let rawContents = makeChatGPTAuthJSON(
            accountID: "acct-credentials",
            subject: "auth0|acct-credentials",
            email: "limits@example.com"
        )

        let credentials = try CodexAuthFile.parseRateLimitCredentials(contents: rawContents)

        #expect(credentials.authMode == .chatgpt)
        #expect(credentials.identityKey.hasPrefix("chatgpt:"))
        #expect(credentials.accountID == "acct-credentials")
        #expect(credentials.accessToken != nil)
        #expect(credentials.idToken != nil)
    }

    @Test func capturePreventsDuplicatesAndKeepsSelectionOnExistingAccount() async throws {
        let container = try makeInMemoryContainer()
        let authFileManager = FakeAuthFileManager(contents: makeChatGPTAuthJSON(accountID: "acct-123"))
        let secretStore = FakeSecretStore()
        let syncedRateLimitCredentialStore = FakeSyncedRateLimitCredentialStore()
        let controller = makeController(
            authFileManager: authFileManager,
            secretStore: secretStore,
            syncedRateLimitCredentialStore: syncedRateLimitCredentialStore
        )

        controller.configure(modelContext: container.mainContext, undoManager: nil)
        await controller.captureCurrentAccountNow()
        await controller.captureCurrentAccountNow()

        let accounts = try fetchAccounts(in: container.mainContext)
        let account = try #require(accounts.first)

        #expect(accounts.count == 1)
        #expect(controller.selection == [account.id])
        #expect(account.name == "acct-123@example.com")
        #expect(account.iconSystemName == AccountIconOption.defaultOption.systemName)
        #expect(account.authFileContents == nil)
        #expect(account.hasLocalSnapshot == false)
        #expect(await secretStore.secret(forIdentityKey: account.identityKey) == makeChatGPTAuthJSON(accountID: "acct-123"))
        #expect(await syncedRateLimitCredentialStore.containsCredential(forIdentityKey: account.identityKey))
        #expect(await syncedRateLimitCredentialStore.saveCallCount() == 1)
    }

    @Test func captureFallsBackToGeneratedNameWhenEmailUnknown() async throws {
        let container = try makeInMemoryContainer()
        let controller = makeController(
            authFileManager: FakeAuthFileManager(
                contents: """
                {
                  "auth_mode": "apiKey",
                  "OPENAI_API_KEY": "sk-test-123"
                }
                """
            )
        )

        controller.configure(modelContext: container.mainContext, undoManager: nil)
        await controller.captureCurrentAccountNow()

        let account = try #require(fetchAccounts(in: container.mainContext).first)
        #expect(account.name == "Account 1")
    }

    @Test func captureAddsDistinctAccountsWhenStableSubjectDiffers() async throws {
        let container = try makeInMemoryContainer()
        let authFileManager = FakeAuthFileManager(
            contents: makeChatGPTAuthJSON(
                accountID: "shared-account-id",
                userID: "user-one",
                subject: "auth0|user-one",
                email: "one@example.com"
            )
        )
        let controller = makeController(authFileManager: authFileManager)

        controller.configure(modelContext: container.mainContext, undoManager: nil)
        await controller.captureCurrentAccountNow()

        await authFileManager.setContents(
            makeChatGPTAuthJSON(
                accountID: "shared-account-id",
                userID: "user-two",
                subject: "auth0|user-two",
                email: "two@example.com"
            )
        )

        await controller.captureCurrentAccountNow()

        let accounts = try fetchAccounts(in: container.mainContext)
        #expect(accounts.count == 2)
        #expect(Set(accounts.map(\.emailHint)) == ["one@example.com", "two@example.com"])
    }

    @Test func captureClearsActiveSearchFilter() async throws {
        let container = try makeInMemoryContainer()
        let controller = makeController(
            authFileManager: FakeAuthFileManager(contents: makeChatGPTAuthJSON(accountID: "acct-123"))
        )

        controller.configure(modelContext: container.mainContext, undoManager: nil)
        controller.searchText = "something"

        await controller.captureCurrentAccountNow()

        #expect(controller.searchText.isEmpty)
    }

    @Test func storedSnapshotsStaySyncedAndBackfillTheLocalKeychainCache() async throws {
        let container = try makeInMemoryContainer()
        let secretStore = FakeSecretStore()
        let syncedRateLimitCredentialStore = FakeSyncedRateLimitCredentialStore()
        let controller = makeController(
            authFileManager: FakeAuthFileManager(contents: makeChatGPTAuthJSON(accountID: "acct-current")),
            secretStore: secretStore,
            syncedRateLimitCredentialStore: syncedRateLimitCredentialStore
        )

        let legacyContents = makeChatGPTAuthJSON(accountID: "acct-legacy")
        let legacySnapshot = try CodexAuthFile.parse(contents: legacyContents)
        container.mainContext.insert(
            StoredAccount(
                identityKey: legacySnapshot.identityKey,
                name: "Legacy",
                customOrder: 0,
                authFileContents: legacyContents,
                authModeRaw: legacySnapshot.authMode.rawValue,
                emailHint: legacySnapshot.email,
                accountIdentifier: legacySnapshot.accountIdentifier
            )
        )
        try container.mainContext.save()

        controller.configure(modelContext: container.mainContext, undoManager: nil)
        await Task.yield()
        await controller.refreshAuthStateForTesting()

        let migratedAccount = try #require(fetchAccounts(in: container.mainContext).first)
        #expect(migratedAccount.authFileContents == nil)
        #expect(migratedAccount.hasLocalSnapshot == false)
        #expect(await secretStore.secret(forIdentityKey: migratedAccount.identityKey) == legacyContents)
        #expect(await syncedRateLimitCredentialStore.containsCredential(forIdentityKey: migratedAccount.identityKey))
    }

    @Test func importingUnchangedArchiveForExistingAccountStillSucceeds() async throws {
        let container = try makeInMemoryContainer()
        let snapshotContents = makeChatGPTAuthJSON(accountID: "acct-import")
        let snapshot = try CodexAuthFile.parse(contents: snapshotContents)
        let secretStore = FakeSecretStore()
        let controller = makeController(
            authFileManager: FakeAuthFileManager(contents: snapshotContents),
            secretStore: secretStore
        )
        let existingAccount = StoredAccount(
            identityKey: snapshot.identityKey,
            name: snapshot.email ?? "Imported Account",
            customOrder: 0,
            hasLocalSnapshot: true,
            authModeRaw: snapshot.authMode.rawValue,
            emailHint: snapshot.email,
            accountIdentifier: snapshot.accountIdentifier
        )
        let archive = CodexAccountArchive(
            name: existingAccount.name,
            iconSystemName: existingAccount.iconSystemName,
            identityKey: snapshot.identityKey,
            authModeRaw: snapshot.authMode.rawValue,
            emailHint: snapshot.email,
            accountIdentifier: snapshot.accountIdentifier,
            snapshotContents: snapshotContents
        )
        let archiveDirectoryURL = try makeTemporaryDirectory()
        let archiveURL = archiveDirectoryURL.appendingPathComponent("existing-account.cxa", isDirectory: false)

        try await secretStore.saveSnapshot(snapshotContents, forIdentityKey: snapshot.identityKey)
        await secretStore.resetSaveCallCount()
        container.mainContext.insert(existingAccount)
        try container.mainContext.save()
        controller.configure(modelContext: container.mainContext, undoManager: nil)
        try archive.encodedData().write(to: archiveURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: archiveDirectoryURL) }

        let didImport = await controller.importAccountArchivesForTesting(from: [archiveURL])
        let importedAccounts = try fetchAccounts(in: container.mainContext)

        #expect(didImport)
        #expect(importedAccounts.count == 1)
        #expect(controller.selection == [existingAccount.id])
        #expect(secretStore.saveCallCount == 0)
        #expect(await secretStore.secret(forIdentityKey: snapshot.identityKey) == snapshotContents)
    }

    @Test func refreshMarksUnsupportedCredentialStoresInline() async throws {
        let container = try makeInMemoryContainer()
        let authFileManager = FakeAuthFileManager(
            contents: makeChatGPTAuthJSON(accountID: "acct-123"),
            linkedLocation: AuthLinkedLocation(
                folderURL: URL(fileURLWithPath: "/tmp/custom-codex", isDirectory: true),
                credentialStoreHint: .auto
            )
        )
        let controller = makeController(authFileManager: authFileManager)

        controller.configure(modelContext: container.mainContext, undoManager: nil)
        await controller.refreshAuthStateForTesting()

        #expect(controller.authAccessState == .unsupportedCredentialStore(
            linkedFolder: URL(fileURLWithPath: "/tmp/custom-codex", isDirectory: true),
            mode: .auto
        ))
        #expect(controller.activeIdentityKey == nil)
    }

    @Test func missingAuthFileIsTreatedAsLoggedOutWithoutInlineBanner() {
        let state = AuthAccessState.missingAuthFile(
            linkedFolder: URL(fileURLWithPath: "/tmp/.codex", isDirectory: true),
            credentialStoreHint: .file
        )

        #expect(state.showsInlineStatus == false)
        #expect(state.linkedFolderURL?.path == "/tmp/.codex")
    }

    @Test func switchingAccountWritesStoredSnapshotAndRefreshesLastLogin() async throws {
        let container = try makeInMemoryContainer()
        let authFileManager = FakeAuthFileManager(contents: makeChatGPTAuthJSON(accountID: "acct-original"))
        let secretStore = FakeSecretStore()
        let notificationManager = FakeNotificationManager()
        let controller = makeController(
            authFileManager: authFileManager,
            secretStore: secretStore,
            notificationManager: notificationManager
        )

        controller.configure(modelContext: container.mainContext, undoManager: nil)

        let targetContents = makeChatGPTAuthJSON(accountID: "acct-target")
        let targetSnapshot = try CodexAuthFile.parse(contents: targetContents)
        let account = StoredAccount(
            identityKey: targetSnapshot.identityKey,
            name: "Account 1",
            customOrder: 0,
            authModeRaw: targetSnapshot.authMode.rawValue,
            emailHint: targetSnapshot.email,
            accountIdentifier: targetSnapshot.accountIdentifier
        )
        container.mainContext.insert(account)
        try container.mainContext.save()
        try await secretStore.saveSecret(targetContents, for: account.id)

        await controller.switchToAccountNow(id: account.id)

        let refreshedAccount = try #require(fetchAccounts(in: container.mainContext).first)
        #expect(await authFileManager.currentContents == targetContents)
        #expect(refreshedAccount.lastLoginAt != nil)
        #expect(controller.selection == [account.id])
        #expect(notificationManager.postedAccountNames == ["Account 1"])
    }

    @Test func switchingToTheAlreadyActiveAccountSkipsRewriteAndNotification() async throws {
        let container = try makeInMemoryContainer()
        let currentContents = makeChatGPTAuthJSON(accountID: "acct-current")
        let authFileManager = FakeAuthFileManager(contents: currentContents)
        let notificationManager = FakeNotificationManager()
        let controller = makeController(
            authFileManager: authFileManager,
            notificationManager: notificationManager
        )

        let currentSnapshot = try CodexAuthFile.parse(contents: currentContents)
        let currentAccount = StoredAccount(
            identityKey: currentSnapshot.identityKey,
            name: "Current",
            customOrder: 0,
            authFileContents: currentContents,
            authModeRaw: currentSnapshot.authMode.rawValue,
            emailHint: currentSnapshot.email,
            accountIdentifier: currentSnapshot.accountIdentifier
        )
        container.mainContext.insert(currentAccount)
        try container.mainContext.save()

        controller.configure(modelContext: container.mainContext, undoManager: nil)
        await controller.refreshAuthStateForTesting()
        await controller.switchToAccountNow(id: currentAccount.id)

        #expect(await authFileManager.writeCallCount == 0)
        #expect(await authFileManager.currentContents == currentContents)
        #expect(controller.activeIdentityKey == currentSnapshot.identityKey)
        #expect(controller.selection == [currentAccount.id])
        #expect(notificationManager.postedAccountNames.isEmpty)
    }

    @Test func dockAccountsFollowAppSortOrderAndLimitSwitchableAccounts() async throws {
        let container = try makeInMemoryContainer()
        let currentContents = makeChatGPTAuthJSON(accountID: "acct-current")
        let authFileManager = FakeAuthFileManager(contents: currentContents)
        let controller = makeController(authFileManager: authFileManager)

        let currentSnapshot = try CodexAuthFile.parse(contents: currentContents)
        let currentAccount = StoredAccount(
            identityKey: currentSnapshot.identityKey,
            name: "Delta",
            customOrder: 0,
            hasLocalSnapshot: true,
            authModeRaw: currentSnapshot.authMode.rawValue,
            emailHint: currentSnapshot.email,
            accountIdentifier: currentSnapshot.accountIdentifier
        )

        let bravoContents = makeChatGPTAuthJSON(accountID: "acct-bravo")
        let bravoSnapshot = try CodexAuthFile.parse(contents: bravoContents)
        let bravoAccount = StoredAccount(
            identityKey: bravoSnapshot.identityKey,
            name: "Bravo",
            customOrder: 1,
            hasLocalSnapshot: true,
            authModeRaw: bravoSnapshot.authMode.rawValue,
            emailHint: bravoSnapshot.email,
            accountIdentifier: bravoSnapshot.accountIdentifier,
            iconSystemName: AccountIconOption.briefcase.systemName
        )

        let echoContents = makeChatGPTAuthJSON(accountID: "acct-echo")
        let echoSnapshot = try CodexAuthFile.parse(contents: echoContents)
        let echoAccount = StoredAccount(
            identityKey: echoSnapshot.identityKey,
            name: "Echo",
            customOrder: 2,
            hasLocalSnapshot: true,
            authModeRaw: echoSnapshot.authMode.rawValue,
            emailHint: echoSnapshot.email,
            accountIdentifier: echoSnapshot.accountIdentifier,
            iconSystemName: AccountIconOption.house.systemName
        )

        let alphaContents = makeChatGPTAuthJSON(accountID: "acct-alpha")
        let alphaSnapshot = try CodexAuthFile.parse(contents: alphaContents)
        let alphaAccount = StoredAccount(
            identityKey: alphaSnapshot.identityKey,
            name: "Alpha",
            customOrder: 3,
            hasLocalSnapshot: true,
            authModeRaw: alphaSnapshot.authMode.rawValue,
            emailHint: alphaSnapshot.email,
            accountIdentifier: alphaSnapshot.accountIdentifier
        )

        let charlieContents = makeChatGPTAuthJSON(accountID: "acct-charlie")
        let charlieSnapshot = try CodexAuthFile.parse(contents: charlieContents)
        let charlieAccount = StoredAccount(
            identityKey: charlieSnapshot.identityKey,
            name: "Charlie",
            customOrder: 4,
            hasLocalSnapshot: true,
            authModeRaw: charlieSnapshot.authMode.rawValue,
            emailHint: charlieSnapshot.email,
            accountIdentifier: charlieSnapshot.accountIdentifier
        )

        let foxtrotContents = makeChatGPTAuthJSON(accountID: "acct-foxtrot")
        let foxtrotSnapshot = try CodexAuthFile.parse(contents: foxtrotContents)
        let foxtrotAccount = StoredAccount(
            identityKey: foxtrotSnapshot.identityKey,
            name: "Foxtrot",
            customOrder: 5,
            hasLocalSnapshot: true,
            authModeRaw: foxtrotSnapshot.authMode.rawValue,
            emailHint: foxtrotSnapshot.email,
            accountIdentifier: foxtrotSnapshot.accountIdentifier
        )

        let noSnapshotContents = makeChatGPTAuthJSON(accountID: "acct-no-snapshot")
        let noSnapshotSnapshot = try CodexAuthFile.parse(contents: noSnapshotContents)
        let noSnapshotAccount = StoredAccount(
            identityKey: noSnapshotSnapshot.identityKey,
            name: "Able",
            customOrder: 6,
            hasLocalSnapshot: false,
            authModeRaw: noSnapshotSnapshot.authMode.rawValue,
            emailHint: noSnapshotSnapshot.email,
            accountIdentifier: noSnapshotSnapshot.accountIdentifier
        )

        container.mainContext.insert(currentAccount)
        container.mainContext.insert(bravoAccount)
        container.mainContext.insert(echoAccount)
        container.mainContext.insert(alphaAccount)
        container.mainContext.insert(charlieAccount)
        container.mainContext.insert(foxtrotAccount)
        container.mainContext.insert(noSnapshotAccount)
        try container.mainContext.save()

        controller.configure(modelContext: container.mainContext, undoManager: nil)
        await controller.refreshAuthStateForTesting()
        controller.sortCriterion = .name
        controller.sortDirection = .ascending

        let dockAccounts = controller.dockAccounts(limit: 5)
        let expectedIDs = [
            alphaAccount.id,
            bravoAccount.id,
            charlieAccount.id,
            currentAccount.id,
            echoAccount.id,
        ]
        let expectedTitles = ["Alpha", "Bravo", "Charlie", "Delta", "Echo"]
        let expectedIcons = [
            AccountIconOption.defaultOption.systemName,
            AccountIconOption.briefcase.systemName,
            AccountIconOption.defaultOption.systemName,
            AccountIconOption.defaultOption.systemName,
            AccountIconOption.house.systemName,
        ]
        let expectedCurrentFlags = [false, false, false, true, false]

        #expect(dockAccounts.count == 5)
        #expect(dockAccounts.map(\.id) == expectedIDs)
        #expect(dockAccounts.map(\.title) == expectedTitles)
        #expect(dockAccounts.map(\.iconSystemName) == expectedIcons)
        #expect(dockAccounts.map(\.isCurrentAccount) == expectedCurrentFlags)
    }

    @Test func autopilotSwitchesToTheBestRateLimitAccountAndNotifiesOnlyOnRealChange() async throws {
        let container = try makeInMemoryContainer()
        let currentContents = makeChatGPTAuthJSON(accountID: "acct-current")
        let betterContents = makeChatGPTAuthJSON(accountID: "acct-better")
        let authFileManager = FakeAuthFileManager(contents: currentContents)
        let notificationManager = FakeNotificationManager()
        let rateLimitProvider = FakeRateLimitProvider()
        let controller = makeController(
            authFileManager: authFileManager,
            notificationManager: notificationManager,
            rateLimitProvider: rateLimitProvider
        )

        let currentSnapshot = try CodexAuthFile.parse(contents: currentContents)
        let betterSnapshot = try CodexAuthFile.parse(contents: betterContents)
        let currentAccount = StoredAccount(
            identityKey: currentSnapshot.identityKey,
            name: "Current",
            customOrder: 0,
            authFileContents: currentContents,
            authModeRaw: currentSnapshot.authMode.rawValue,
            emailHint: currentSnapshot.email,
            accountIdentifier: currentSnapshot.accountIdentifier
        )
        let betterAccount = StoredAccount(
            identityKey: betterSnapshot.identityKey,
            name: "Better",
            customOrder: 1,
            authFileContents: betterContents,
            authModeRaw: betterSnapshot.authMode.rawValue,
            emailHint: betterSnapshot.email,
            accountIdentifier: betterSnapshot.accountIdentifier
        )
        container.mainContext.insert(currentAccount)
        container.mainContext.insert(betterAccount)
        try container.mainContext.save()

        await rateLimitProvider.setSnapshot(
            makeRateLimitSnapshot(
                identityKey: currentSnapshot.identityKey,
                sevenDayRemainingPercent: 45,
                fiveHourRemainingPercent: 40
            ),
            for: currentSnapshot.identityKey
        )
        await rateLimitProvider.setSnapshot(
            makeRateLimitSnapshot(
                identityKey: betterSnapshot.identityKey,
                sevenDayRemainingPercent: 80,
                fiveHourRemainingPercent: 70
            ),
            for: betterSnapshot.identityKey
        )

        controller.configure(modelContext: container.mainContext, undoManager: nil)
        await controller.refreshAuthStateForTesting()
        await controller.runAutopilotCheckForTesting()

        #expect(await authFileManager.currentContents == betterContents)
        #expect(await authFileManager.writeCallCount == 1)
        #expect(controller.activeIdentityKey == betterSnapshot.identityKey)
        #expect(controller.selection == [betterAccount.id])
        #expect(notificationManager.postedAccountNames == ["Better"])
    }

    @Test func autopilotEvaluatesImmediatelyWhenAppLaunches() async throws {
        let container = try makeInMemoryContainer()
        let currentContents = makeChatGPTAuthJSON(accountID: "acct-launch-current")
        let betterContents = makeChatGPTAuthJSON(accountID: "acct-launch-better")
        let authFileManager = FakeAuthFileManager(contents: currentContents)
        let notificationManager = FakeNotificationManager()
        let rateLimitProvider = FakeRateLimitProvider()
        let controller = makeController(
            authFileManager: authFileManager,
            notificationManager: notificationManager,
            rateLimitProvider: rateLimitProvider
        )

        let currentSnapshot = try CodexAuthFile.parse(contents: currentContents)
        let betterSnapshot = try CodexAuthFile.parse(contents: betterContents)
        container.mainContext.insert(
            StoredAccount(
                identityKey: currentSnapshot.identityKey,
                name: "Current",
                customOrder: 0,
                authFileContents: currentContents,
                authModeRaw: currentSnapshot.authMode.rawValue,
                emailHint: currentSnapshot.email,
                accountIdentifier: currentSnapshot.accountIdentifier
            )
        )
        let betterAccount = StoredAccount(
            identityKey: betterSnapshot.identityKey,
            name: "Better",
            customOrder: 1,
            authFileContents: betterContents,
            authModeRaw: betterSnapshot.authMode.rawValue,
            emailHint: betterSnapshot.email,
            accountIdentifier: betterSnapshot.accountIdentifier
        )
        container.mainContext.insert(betterAccount)
        try container.mainContext.save()

        await rateLimitProvider.setSnapshot(
            makeRateLimitSnapshot(
                identityKey: currentSnapshot.identityKey,
                sevenDayRemainingPercent: 40,
                fiveHourRemainingPercent: 35
            ),
            for: currentSnapshot.identityKey
        )
        await rateLimitProvider.setSnapshot(
            makeRateLimitSnapshot(
                identityKey: betterSnapshot.identityKey,
                sevenDayRemainingPercent: 90,
                fiveHourRemainingPercent: 80
            ),
            for: betterSnapshot.identityKey
        )

        controller.configure(modelContext: container.mainContext, undoManager: nil)
        await controller.runAutopilotLaunchTriggerForTesting()

        #expect(controller.activeIdentityKey == betterSnapshot.identityKey)
        #expect(controller.selection == [betterAccount.id])
        #expect(notificationManager.postedAccountNames == ["Better"])
    }

    @Test func autopilotReevaluatesImmediatelyWhenAppBecomesActive() async throws {
        let container = try makeInMemoryContainer()
        let currentContents = makeChatGPTAuthJSON(accountID: "acct-focus-current")
        let betterContents = makeChatGPTAuthJSON(accountID: "acct-focus-better")
        let authFileManager = FakeAuthFileManager(contents: currentContents)
        let notificationManager = FakeNotificationManager()
        let rateLimitProvider = FakeRateLimitProvider()
        let controller = makeController(
            authFileManager: authFileManager,
            notificationManager: notificationManager,
            rateLimitProvider: rateLimitProvider
        )

        let currentSnapshot = try CodexAuthFile.parse(contents: currentContents)
        let betterSnapshot = try CodexAuthFile.parse(contents: betterContents)
        let currentAccount = StoredAccount(
            identityKey: currentSnapshot.identityKey,
            name: "Current",
            customOrder: 0,
            authFileContents: currentContents,
            authModeRaw: currentSnapshot.authMode.rawValue,
            emailHint: currentSnapshot.email,
            accountIdentifier: currentSnapshot.accountIdentifier
        )
        let betterAccount = StoredAccount(
            identityKey: betterSnapshot.identityKey,
            name: "Better",
            customOrder: 1,
            authFileContents: betterContents,
            authModeRaw: betterSnapshot.authMode.rawValue,
            emailHint: betterSnapshot.email,
            accountIdentifier: betterSnapshot.accountIdentifier
        )
        container.mainContext.insert(currentAccount)
        container.mainContext.insert(betterAccount)
        try container.mainContext.save()

        await rateLimitProvider.setSnapshot(
            makeRateLimitSnapshot(
                identityKey: currentSnapshot.identityKey,
                sevenDayRemainingPercent: 95,
                fiveHourRemainingPercent: 90
            ),
            for: currentSnapshot.identityKey
        )
        await rateLimitProvider.setSnapshot(
            makeRateLimitSnapshot(
                identityKey: betterSnapshot.identityKey,
                sevenDayRemainingPercent: 60,
                fiveHourRemainingPercent: 55
            ),
            for: betterSnapshot.identityKey
        )

        controller.configure(modelContext: container.mainContext, undoManager: nil)
        await controller.refreshAuthStateForTesting()

        await rateLimitProvider.setSnapshot(
            makeRateLimitSnapshot(
                identityKey: currentSnapshot.identityKey,
                sevenDayRemainingPercent: 20,
                fiveHourRemainingPercent: 15
            ),
            for: currentSnapshot.identityKey
        )
        await rateLimitProvider.setSnapshot(
            makeRateLimitSnapshot(
                identityKey: betterSnapshot.identityKey,
                sevenDayRemainingPercent: 85,
                fiveHourRemainingPercent: 75
            ),
            for: betterSnapshot.identityKey
        )

        controller.setApplicationActive(false)
        controller.setApplicationActive(true)
        await controller.runAutopilotFocusTriggerForTesting()

        #expect(controller.activeIdentityKey == betterSnapshot.identityKey)
        #expect(controller.selection == [betterAccount.id])
        #expect(notificationManager.postedAccountNames == ["Better"])
    }

    @Test func autopilotReevaluatesImmediatelyWhenMacWakes() async throws {
        let container = try makeInMemoryContainer()
        let currentContents = makeChatGPTAuthJSON(accountID: "acct-wake-current")
        let betterContents = makeChatGPTAuthJSON(accountID: "acct-wake-better")
        let authFileManager = FakeAuthFileManager(contents: currentContents)
        let notificationManager = FakeNotificationManager()
        let rateLimitProvider = FakeRateLimitProvider()
        let controller = makeController(
            authFileManager: authFileManager,
            notificationManager: notificationManager,
            rateLimitProvider: rateLimitProvider
        )

        let currentSnapshot = try CodexAuthFile.parse(contents: currentContents)
        let betterSnapshot = try CodexAuthFile.parse(contents: betterContents)
        let currentAccount = StoredAccount(
            identityKey: currentSnapshot.identityKey,
            name: "Current",
            customOrder: 0,
            authFileContents: currentContents,
            authModeRaw: currentSnapshot.authMode.rawValue,
            emailHint: currentSnapshot.email,
            accountIdentifier: currentSnapshot.accountIdentifier
        )
        let betterAccount = StoredAccount(
            identityKey: betterSnapshot.identityKey,
            name: "Better",
            customOrder: 1,
            authFileContents: betterContents,
            authModeRaw: betterSnapshot.authMode.rawValue,
            emailHint: betterSnapshot.email,
            accountIdentifier: betterSnapshot.accountIdentifier
        )
        container.mainContext.insert(currentAccount)
        container.mainContext.insert(betterAccount)
        try container.mainContext.save()

        await rateLimitProvider.setSnapshot(
            makeRateLimitSnapshot(
                identityKey: currentSnapshot.identityKey,
                sevenDayRemainingPercent: 90,
                fiveHourRemainingPercent: 85
            ),
            for: currentSnapshot.identityKey
        )
        await rateLimitProvider.setSnapshot(
            makeRateLimitSnapshot(
                identityKey: betterSnapshot.identityKey,
                sevenDayRemainingPercent: 70,
                fiveHourRemainingPercent: 65
            ),
            for: betterSnapshot.identityKey
        )

        controller.configure(modelContext: container.mainContext, undoManager: nil)
        await controller.refreshAuthStateForTesting()

        await rateLimitProvider.setSnapshot(
            makeRateLimitSnapshot(
                identityKey: currentSnapshot.identityKey,
                sevenDayRemainingPercent: 25,
                fiveHourRemainingPercent: 20
            ),
            for: currentSnapshot.identityKey
        )
        await rateLimitProvider.setSnapshot(
            makeRateLimitSnapshot(
                identityKey: betterSnapshot.identityKey,
                sevenDayRemainingPercent: 88,
                fiveHourRemainingPercent: 81
            ),
            for: betterSnapshot.identityKey
        )

        await controller.runAutopilotWakeTriggerForTesting()

        #expect(controller.activeIdentityKey == betterSnapshot.identityKey)
        #expect(controller.selection == [betterAccount.id])
        #expect(notificationManager.postedAccountNames == ["Better"])
    }

    @Test func scheduledAutopilotPausesInLowPowerModeButWakeTriggerStillRuns() async throws {
        let container = try makeInMemoryContainer()
        let currentContents = makeChatGPTAuthJSON(accountID: "acct-lowpower-current")
        let betterContents = makeChatGPTAuthJSON(accountID: "acct-lowpower-better")
        let authFileManager = FakeAuthFileManager(contents: currentContents)
        let notificationManager = FakeNotificationManager()
        let rateLimitProvider = FakeRateLimitProvider()
        let powerState = TestPowerStateSource(lowPowerModeEnabled: true, batteryChargePercent: 72)
        let controller = makeController(
            authFileManager: authFileManager,
            notificationManager: notificationManager,
            rateLimitProvider: rateLimitProvider,
            lowPowerModeProvider: { powerState.lowPowerModeEnabled },
            batteryChargePercentProvider: { powerState.batteryChargePercent }
        )

        let currentSnapshot = try CodexAuthFile.parse(contents: currentContents)
        let betterSnapshot = try CodexAuthFile.parse(contents: betterContents)
        container.mainContext.insert(
            StoredAccount(
                identityKey: currentSnapshot.identityKey,
                name: "Current",
                customOrder: 0,
                authFileContents: currentContents,
                authModeRaw: currentSnapshot.authMode.rawValue,
                emailHint: currentSnapshot.email,
                accountIdentifier: currentSnapshot.accountIdentifier
            )
        )
        let betterAccount = StoredAccount(
            identityKey: betterSnapshot.identityKey,
            name: "Better",
            customOrder: 1,
            authFileContents: betterContents,
            authModeRaw: betterSnapshot.authMode.rawValue,
            emailHint: betterSnapshot.email,
            accountIdentifier: betterSnapshot.accountIdentifier
        )
        container.mainContext.insert(betterAccount)
        try container.mainContext.save()

        await rateLimitProvider.setSnapshot(
            makeRateLimitSnapshot(
                identityKey: currentSnapshot.identityKey,
                sevenDayRemainingPercent: 25,
                fiveHourRemainingPercent: 20
            ),
            for: currentSnapshot.identityKey
        )
        await rateLimitProvider.setSnapshot(
            makeRateLimitSnapshot(
                identityKey: betterSnapshot.identityKey,
                sevenDayRemainingPercent: 88,
                fiveHourRemainingPercent: 81
            ),
            for: betterSnapshot.identityKey
        )

        controller.configure(modelContext: container.mainContext, undoManager: nil)
        await controller.refreshAuthStateForTesting()

        #expect(controller.scheduledAutopilotWouldRunNowForTesting() == false)

        await controller.runAutopilotWakeTriggerForTesting()

        #expect(controller.activeIdentityKey == betterSnapshot.identityKey)
        #expect(controller.selection == [betterAccount.id])
        #expect(notificationManager.postedAccountNames == ["Better"])
    }

    @Test func autopilotReevaluatesWhenRecentSessionActivityBecomesQuiet() async throws {
        let container = try makeInMemoryContainer()
        let currentContents = makeChatGPTAuthJSON(accountID: "acct-task-current")
        let betterContents = makeChatGPTAuthJSON(accountID: "acct-task-better")
        let authFileManager = FakeAuthFileManager(contents: currentContents)
        let notificationManager = FakeNotificationManager()
        let rateLimitProvider = FakeRateLimitProvider()
        let controller = makeController(
            authFileManager: authFileManager,
            notificationManager: notificationManager,
            rateLimitProvider: rateLimitProvider
        )

        let currentSnapshot = try CodexAuthFile.parse(contents: currentContents)
        let betterSnapshot = try CodexAuthFile.parse(contents: betterContents)
        let currentAccount = StoredAccount(
            identityKey: currentSnapshot.identityKey,
            name: "Current",
            customOrder: 0,
            authFileContents: currentContents,
            authModeRaw: currentSnapshot.authMode.rawValue,
            emailHint: currentSnapshot.email,
            accountIdentifier: currentSnapshot.accountIdentifier
        )
        let betterAccount = StoredAccount(
            identityKey: betterSnapshot.identityKey,
            name: "Better",
            customOrder: 1,
            authFileContents: betterContents,
            authModeRaw: betterSnapshot.authMode.rawValue,
            emailHint: betterSnapshot.email,
            accountIdentifier: betterSnapshot.accountIdentifier
        )
        container.mainContext.insert(currentAccount)
        container.mainContext.insert(betterAccount)
        try container.mainContext.save()

        await rateLimitProvider.setSnapshot(
            makeRateLimitSnapshot(
                identityKey: currentSnapshot.identityKey,
                sevenDayRemainingPercent: 94,
                fiveHourRemainingPercent: 90
            ),
            for: currentSnapshot.identityKey
        )
        await rateLimitProvider.setSnapshot(
            makeRateLimitSnapshot(
                identityKey: betterSnapshot.identityKey,
                sevenDayRemainingPercent: 82,
                fiveHourRemainingPercent: 80
            ),
            for: betterSnapshot.identityKey
        )

        controller.configure(modelContext: container.mainContext, undoManager: nil)
        await controller.refreshAuthStateForTesting()

        await rateLimitProvider.setSnapshot(
            makeRateLimitSnapshot(
                identityKey: currentSnapshot.identityKey,
                sevenDayRemainingPercent: 35,
                fiveHourRemainingPercent: 30
            ),
            for: currentSnapshot.identityKey
        )
        await controller.runAutopilotSessionQuietTriggerForTesting(
            observedAt: Date().addingTimeInterval(-60)
        )

        #expect(controller.activeIdentityKey == betterSnapshot.identityKey)
        #expect(controller.selection == [betterAccount.id])
        #expect(notificationManager.postedAccountNames == ["Better"])
    }

    @Test func remoteSwitchSignalRefreshesRunningControllerWithoutManualOpen() async throws {
        let container = try makeInMemoryContainer()
        let authFileManager = FakeAuthFileManager(contents: makeChatGPTAuthJSON(accountID: "acct-original"))
        let notificationManager = FakeNotificationManager()
        let controller = makeController(
            authFileManager: authFileManager,
            notificationManager: notificationManager
        )

        let targetContents = makeChatGPTAuthJSON(accountID: "acct-remote-target")
        let targetSnapshot = try CodexAuthFile.parse(contents: targetContents)
        let targetAccount = StoredAccount(
            identityKey: targetSnapshot.identityKey,
            name: "Remote Target",
            customOrder: 0,
            authModeRaw: targetSnapshot.authMode.rawValue,
            emailHint: targetSnapshot.email,
            accountIdentifier: targetSnapshot.accountIdentifier
        )
        container.mainContext.insert(targetAccount)
        try container.mainContext.save()
        let targetAccountID = targetAccount.id
        let targetIdentityKey = targetSnapshot.identityKey

        controller.configure(modelContext: container.mainContext, undoManager: nil)
        await controller.refreshAuthStateForTesting()

        await authFileManager.setContents(targetContents)
        await controller.handleRemoteSwitchSignalForTesting(
            CodexSharedSwitchSignal(
                identityKey: targetIdentityKey,
                accountName: targetAccount.name
            )
        )

        #expect(controller.activeIdentityKey == targetIdentityKey)
        #expect(controller.selection == [targetAccountID])
        #expect(controller.authAccessState == .ready(
            linkedFolder: URL(fileURLWithPath: "/tmp/.codex", isDirectory: true)
        ))
        #expect(notificationManager.postedAccountNames.isEmpty)
    }

    @Test func focusingAppImmediatelyRefreshesVisibleAccountRateLimits() async throws {
        let container = try makeInMemoryContainer()
        let authFileManager = FakeAuthFileManager(contents: makeChatGPTAuthJSON(accountID: "acct-focus"))
        let rateLimitProvider = FakeRateLimitProvider()
        let controller = makeController(
            authFileManager: authFileManager,
            rateLimitProvider: rateLimitProvider
        )

        let contents = makeChatGPTAuthJSON(accountID: "acct-focus")
        let snapshot = try CodexAuthFile.parse(contents: contents)
        let account = StoredAccount(
            identityKey: snapshot.identityKey,
            name: "Focus",
            customOrder: 0,
            authFileContents: contents,
            authModeRaw: snapshot.authMode.rawValue,
            emailHint: snapshot.email,
            accountIdentifier: snapshot.accountIdentifier
        )
        let identityKey = snapshot.identityKey
        container.mainContext.insert(account)
        try container.mainContext.save()
        await rateLimitProvider.setSnapshot(makeRateLimitSnapshot(identityKey: identityKey), for: identityKey)

        controller.configure(modelContext: container.mainContext, undoManager: nil)
        await controller.refreshAuthStateForTesting()
        await rateLimitProvider.resetRequests()

        controller.setRateLimitVisibility(true, for: identityKey)
        controller.setApplicationActive(true)

        try await waitUntil {
            await rateLimitProvider.requestCount(for: identityKey) >= 1
        }
    }

    @Test func periodicRateLimitRefreshPausesWhenBatteryIsCriticalButWakeRefreshStillRuns() async throws {
        let container = try makeInMemoryContainer()
        let authFileManager = FakeAuthFileManager(contents: makeChatGPTAuthJSON(accountID: "acct-battery"))
        let rateLimitProvider = FakeRateLimitProvider()
        let powerState = TestPowerStateSource(lowPowerModeEnabled: false, batteryChargePercent: 15)
        let controller = makeController(
            authFileManager: authFileManager,
            rateLimitProvider: rateLimitProvider,
            lowPowerModeProvider: { powerState.lowPowerModeEnabled },
            batteryChargePercentProvider: { powerState.batteryChargePercent }
        )

        let contents = makeChatGPTAuthJSON(accountID: "acct-battery")
        let snapshot = try CodexAuthFile.parse(contents: contents)
        let account = StoredAccount(
            identityKey: snapshot.identityKey,
            name: "Battery",
            customOrder: 0,
            authFileContents: contents,
            authModeRaw: snapshot.authMode.rawValue,
            emailHint: snapshot.email,
            accountIdentifier: snapshot.accountIdentifier
        )
        let identityKey = snapshot.identityKey
        container.mainContext.insert(account)
        try container.mainContext.save()
        await rateLimitProvider.setSnapshot(makeRateLimitSnapshot(identityKey: identityKey), for: identityKey)

        controller.configure(modelContext: container.mainContext, undoManager: nil)
        await controller.refreshAuthStateForTesting()
        controller.setRateLimitVisibility(true, for: identityKey)
        controller.setApplicationActive(true)

        try await waitUntil {
            await rateLimitProvider.requestCount(for: identityKey) >= 1
        }

        await rateLimitProvider.resetRequests()
        await controller.runPeriodicRateLimitRefreshPassForTesting()
        #expect(await rateLimitProvider.requestCount(for: identityKey) == 0)

        controller.handleSystemWakeForTesting()
        try await waitUntil {
            await rateLimitProvider.requestCount(for: identityKey) >= 1
        }
    }

    @Test func captureImmediatelyRefreshesNewAccountRateLimits() async throws {
        let container = try makeInMemoryContainer()
        let authFileManager = FakeAuthFileManager(contents: makeChatGPTAuthJSON(accountID: "acct-capture"))
        let rateLimitProvider = FakeRateLimitProvider()
        let controller = makeController(
            authFileManager: authFileManager,
            rateLimitProvider: rateLimitProvider
        )
        let snapshot = try CodexAuthFile.parse(contents: makeChatGPTAuthJSON(accountID: "acct-capture"))
        let identityKey = snapshot.identityKey
        await rateLimitProvider.setSnapshot(makeRateLimitSnapshot(identityKey: identityKey), for: identityKey)

        controller.configure(modelContext: container.mainContext, undoManager: nil)
        controller.setApplicationActive(true)
        await rateLimitProvider.resetRequests()

        await controller.captureCurrentAccountNow()

        try await waitUntil {
            await rateLimitProvider.requestCount(for: identityKey) >= 1
        }
    }

    @Test func switchingImmediatelyRefreshesTargetAccountRateLimits() async throws {
        let container = try makeInMemoryContainer()
        let authFileManager = FakeAuthFileManager(contents: makeChatGPTAuthJSON(accountID: "acct-original"))
        let secretStore = FakeSecretStore()
        let rateLimitProvider = FakeRateLimitProvider()
        let controller = makeController(
            authFileManager: authFileManager,
            secretStore: secretStore,
            rateLimitProvider: rateLimitProvider
        )

        let targetContents = makeChatGPTAuthJSON(accountID: "acct-target-refresh")
        let targetSnapshot = try CodexAuthFile.parse(contents: targetContents)
        let targetAccount = StoredAccount(
            identityKey: targetSnapshot.identityKey,
            name: "Target",
            customOrder: 0,
            authFileContents: targetContents,
            authModeRaw: targetSnapshot.authMode.rawValue,
            emailHint: targetSnapshot.email,
            accountIdentifier: targetSnapshot.accountIdentifier
        )
        container.mainContext.insert(targetAccount)
        try container.mainContext.save()
        try await secretStore.saveSecret(targetContents, for: targetAccount.id)
        let targetIdentityKey = targetSnapshot.identityKey
        await rateLimitProvider.setSnapshot(makeRateLimitSnapshot(identityKey: targetIdentityKey), for: targetIdentityKey)

        controller.configure(modelContext: container.mainContext, undoManager: nil)
        controller.setApplicationActive(true)
        await rateLimitProvider.resetRequests()

        await controller.switchToAccountNow(id: targetAccount.id)

        try await waitUntil {
            await rateLimitProvider.requestCount(for: targetIdentityKey) >= 1
        }
    }

    @Test func manualRefreshImmediatelyRefreshesCurrentAndVisibleAccounts() async throws {
        let container = try makeInMemoryContainer()
        let authFileManager = FakeAuthFileManager(contents: makeChatGPTAuthJSON(accountID: "acct-current"))
        let rateLimitProvider = FakeRateLimitProvider()
        let controller = makeController(
            authFileManager: authFileManager,
            rateLimitProvider: rateLimitProvider
        )

        let currentContents = makeChatGPTAuthJSON(accountID: "acct-current")
        let currentSnapshot = try CodexAuthFile.parse(contents: currentContents)
        let otherContents = makeChatGPTAuthJSON(accountID: "acct-visible")
        let otherSnapshot = try CodexAuthFile.parse(contents: otherContents)
        let currentIdentityKey = currentSnapshot.identityKey
        let otherIdentityKey = otherSnapshot.identityKey

        container.mainContext.insert(
            StoredAccount(
                identityKey: currentIdentityKey,
                name: "Current",
                customOrder: 0,
                authFileContents: currentContents,
                authModeRaw: currentSnapshot.authMode.rawValue,
                emailHint: currentSnapshot.email,
                accountIdentifier: currentSnapshot.accountIdentifier
            )
        )
        container.mainContext.insert(
            StoredAccount(
                identityKey: otherIdentityKey,
                name: "Visible",
                customOrder: 1,
                authFileContents: otherContents,
                authModeRaw: otherSnapshot.authMode.rawValue,
                emailHint: otherSnapshot.email,
                accountIdentifier: otherSnapshot.accountIdentifier
            )
        )
        try container.mainContext.save()

        await rateLimitProvider.setSnapshot(makeRateLimitSnapshot(identityKey: currentIdentityKey), for: currentIdentityKey)
        await rateLimitProvider.setSnapshot(makeRateLimitSnapshot(identityKey: otherIdentityKey), for: otherIdentityKey)

        controller.configure(modelContext: container.mainContext, undoManager: nil)
        await controller.refreshAuthStateForTesting()
        controller.setApplicationActive(true)
        controller.setRateLimitVisibility(true, for: otherIdentityKey)
        await rateLimitProvider.resetRequests()

        await controller.refreshForTesting()

        try await waitUntil {
            let requestedIdentityKeys = Set(await rateLimitProvider.requestedIdentityKeys())
            return requestedIdentityKeys.contains(currentIdentityKey)
                && requestedIdentityKeys.contains(otherIdentityKey)
        }
    }

    @Test func switchingAccountDoesNotRewriteLocalSecretCacheWhenSyncedSnapshotExists() async throws {
        let container = try makeInMemoryContainer()
        let authFileManager = FakeAuthFileManager(contents: makeChatGPTAuthJSON(accountID: "acct-original"))
        let secretStore = FakeSecretStore()
        let controller = makeController(authFileManager: authFileManager, secretStore: secretStore)

        let targetContents = makeChatGPTAuthJSON(accountID: "acct-target")
        let targetSnapshot = try CodexAuthFile.parse(contents: targetContents)
        let account = StoredAccount(
            identityKey: targetSnapshot.identityKey,
            name: "Target",
            customOrder: 0,
            authFileContents: targetContents,
            authModeRaw: targetSnapshot.authMode.rawValue,
            emailHint: targetSnapshot.email,
            accountIdentifier: targetSnapshot.accountIdentifier
        )
        container.mainContext.insert(account)
        try container.mainContext.save()

        controller.configure(modelContext: container.mainContext, undoManager: nil)
        await controller.refreshAuthStateForTesting()
        await secretStore.resetSaveCallCount()
        await controller.switchToAccountNow(id: account.id)

        #expect(secretStore.saveCallCount == 0)
        #expect(await authFileManager.currentContents == targetContents)
    }

    @Test func switchingAccountRecreatesAuthFileWhenCodexIsLoggedOut() async throws {
        let container = try makeInMemoryContainer()
        let authFileManager = FakeAuthFileManager(
            contents: "",
            linkedLocation: AuthLinkedLocation(
                folderURL: URL(fileURLWithPath: "/tmp/.codex", isDirectory: true),
                credentialStoreHint: .file
            )
        )
        await authFileManager.setMissingAuthFile(true)

        let secretStore = FakeSecretStore()
        let controller = makeController(authFileManager: authFileManager, secretStore: secretStore)

        controller.configure(modelContext: container.mainContext, undoManager: nil)

        let targetContents = makeChatGPTAuthJSON(accountID: "acct-target")
        let targetSnapshot = try CodexAuthFile.parse(contents: targetContents)
        let account = StoredAccount(
            identityKey: targetSnapshot.identityKey,
            name: "Account 1",
            customOrder: 0,
            authModeRaw: targetSnapshot.authMode.rawValue,
            emailHint: targetSnapshot.email,
            accountIdentifier: targetSnapshot.accountIdentifier
        )
        container.mainContext.insert(account)
        try container.mainContext.save()
        try await secretStore.saveSecret(targetContents, for: account.id)

        await controller.switchToAccountNow(id: account.id)

        #expect(await authFileManager.currentContents == targetContents)
        #expect(controller.activeIdentityKey == targetSnapshot.identityKey)
        let storedAccount = try #require(fetchAccounts(in: container.mainContext).first)
        #expect(storedAccount.authFileContents == nil)
        #expect(storedAccount.hasLocalSnapshot == false)
        #expect(await secretStore.secret(forIdentityKey: targetSnapshot.identityKey) == targetContents)
    }

    @Test func cancelledLocationPickerDoesNotShowAlert() async throws {
        let container = try makeInMemoryContainer()
        let controller = makeController(authFileManager: FakeAuthFileManager(contents: makeChatGPTAuthJSON(accountID: "acct-123")))

        controller.configure(modelContext: container.mainContext, undoManager: nil)
        controller.beginLinkingCodexLocation()

        await controller.handleLocationImportForTesting(.failure(CocoaError(.userCancelled)))

        #expect(controller.presentedAlert == nil)
    }

    @Test func selectedAccountIconCanBeChanged() throws {
        let container = try makeInMemoryContainer()
        let controller = makeController(authFileManager: FakeAuthFileManager(contents: makeChatGPTAuthJSON(accountID: "acct-123")))

        controller.configure(modelContext: container.mainContext, undoManager: nil)
        let snapshot = try CodexAuthFile.parse(contents: makeChatGPTAuthJSON(accountID: "acct-123"))
        let account = StoredAccount(
            identityKey: snapshot.identityKey,
            name: "Account 1",
            customOrder: 0,
            authModeRaw: snapshot.authMode.rawValue,
            emailHint: snapshot.email,
            accountIdentifier: snapshot.accountIdentifier
        )
        container.mainContext.insert(account)
        try container.mainContext.save()

        controller.setIcon(.terminal, for: account.id)

        let updatedAccount = try #require(fetchAccounts(in: container.mainContext).first)
        #expect(updatedAccount.iconSystemName == AccountIconOption.terminal.systemName)
    }

    @Test func dragReorderMovesAccountToEndWithoutInvalidInsertIndex() throws {
        let container = try makeInMemoryContainer()
        let controller = makeController(authFileManager: FakeAuthFileManager(contents: makeChatGPTAuthJSON(accountID: "acct-123")))

        controller.configure(modelContext: container.mainContext, undoManager: nil)
        controller.sortCriterion = .custom

        let first = makeStoredAccount(name: "First", customOrder: 0, accountID: "acct-1")
        let second = makeStoredAccount(name: "Second", customOrder: 1, accountID: "acct-2")
        let third = makeStoredAccount(name: "Third", customOrder: 2, accountID: "acct-3")

        container.mainContext.insert(first)
        container.mainContext.insert(second)
        container.mainContext.insert(third)
        try container.mainContext.save()

        controller.reorderDraggedAccounts(
            [first.id.uuidString],
            to: 3,
            visibleAccounts: [first, second, third]
        )

        let reordered = controller.displayedAccounts(from: try fetchAccounts(in: container.mainContext))
        #expect(reordered.map(\.name) == ["Second", "Third", "First"])
        #expect(controller.presentedAlert == nil)
    }

    @Test func pinnedAccountsStayAheadOfUnpinnedAcrossSortModes() {
        let pinnedLater = makeStoredAccount(name: "Zulu", customOrder: 4, accountID: "acct-pinned-later")
        pinnedLater.isPinned = true
        pinnedLater.createdAt = .now.addingTimeInterval(60)

        let pinnedEarlier = makeStoredAccount(name: "Alpha", customOrder: 1, accountID: "acct-pinned-earlier")
        pinnedEarlier.isPinned = true
        pinnedEarlier.createdAt = .now

        let unpinnedEarlier = makeStoredAccount(name: "Bravo", customOrder: 0, accountID: "acct-unpinned-earlier")
        unpinnedEarlier.createdAt = .now.addingTimeInterval(-60)

        let unpinnedLater = makeStoredAccount(name: "Charlie", customOrder: 3, accountID: "acct-unpinned-later")
        unpinnedLater.createdAt = .now.addingTimeInterval(120)

        let accounts = [unpinnedEarlier, pinnedLater, unpinnedLater, pinnedEarlier]

        #expect(
            AccountsPresentationLogic.sortedAccounts(
                from: accounts,
                sortCriterion: .custom,
                sortDirection: .ascending
            )
            .map(\.name) == ["Alpha", "Zulu", "Bravo", "Charlie"]
        )

        #expect(
            AccountsPresentationLogic.sortedAccounts(
                from: accounts,
                sortCriterion: .dateAdded,
                sortDirection: .descending
            )
            .map(\.name) == ["Zulu", "Alpha", "Charlie", "Bravo"]
        )
    }

    @Test func customOrderPersistenceSequenceKeepsPinBoundaryWhilePreservingLaneOrder() {
        let pinnedFirst = makeStoredAccount(name: "Pinned First", customOrder: 0, accountID: "acct-p1")
        pinnedFirst.isPinned = true
        let pinnedSecond = makeStoredAccount(name: "Pinned Second", customOrder: 1, accountID: "acct-p2")
        pinnedSecond.isPinned = true
        let unpinnedFirst = makeStoredAccount(name: "Unpinned First", customOrder: 2, accountID: "acct-u1")
        let unpinnedSecond = makeStoredAccount(name: "Unpinned Second", customOrder: 3, accountID: "acct-u2")

        let persisted = AccountsPresentationLogic.customOrderPersistenceSequence(
            for: [unpinnedSecond, pinnedFirst, unpinnedFirst, pinnedSecond]
        )

        #expect(persisted.map(\.name) == ["Pinned First", "Pinned Second", "Unpinned Second", "Unpinned First"])
    }

    @Test func rateLimitSortUsesMinimumWindowThenMaximumAndKeepsIncompletePairsLast() throws {
        let container = try makeInMemoryContainer()
        let controller = makeController(authFileManager: FakeAuthFileManager(contents: makeChatGPTAuthJSON(accountID: "acct-123")))

        controller.configure(modelContext: container.mainContext, undoManager: nil)
        controller.sortCriterion = .rateLimit

        let first = makeStoredAccount(name: "Min 20 Max 80", customOrder: 0, accountID: "acct-rate-1")
        first.fiveHourLimitUsedPercent = 20
        first.sevenDayLimitUsedPercent = 80

        let second = makeStoredAccount(name: "Min 20 Max 60", customOrder: 1, accountID: "acct-rate-2")
        second.fiveHourLimitUsedPercent = 20
        second.sevenDayLimitUsedPercent = 60

        let third = makeStoredAccount(name: "Min 30 Max 90", customOrder: 2, accountID: "acct-rate-3")
        third.fiveHourLimitUsedPercent = 30
        third.sevenDayLimitUsedPercent = 90

        let unknown = makeStoredAccount(name: "Unknown 5h", customOrder: 3, accountID: "acct-rate-4")
        unknown.fiveHourLimitUsedPercent = nil
        unknown.sevenDayLimitUsedPercent = 70

        container.mainContext.insert(first)
        container.mainContext.insert(second)
        container.mainContext.insert(third)
        container.mainContext.insert(unknown)
        try container.mainContext.save()

        controller.sortDirection = .ascending
        #expect(
            controller.displayedAccounts(from: try fetchAccounts(in: container.mainContext)).map(\.name)
                == ["Min 20 Max 60", "Min 20 Max 80", "Min 30 Max 90", "Unknown 5h"]
        )

        controller.sortDirection = .descending
        #expect(
            controller.displayedAccounts(from: try fetchAccounts(in: container.mainContext)).map(\.name)
                == ["Min 30 Max 90", "Min 20 Max 80", "Min 20 Max 60", "Unknown 5h"]
        )
    }

    @Test func sharedBestAccountCandidateMatchesDescendingRateLimitRanking() {
        let incomplete = makeSharedAccountRecord(
            identityKey: "chatgpt:incomplete",
            name: "Incomplete",
            sortOrder: 0,
            sevenDayLimitUsedPercent: 90,
            fiveHourLimitUsedPercent: nil
        )
        let balanced = makeSharedAccountRecord(
            identityKey: "chatgpt:balanced",
            name: "Balanced",
            sortOrder: 1,
            sevenDayLimitUsedPercent: 70,
            fiveHourLimitUsedPercent: 70
        )
        let best = makeSharedAccountRecord(
            identityKey: "chatgpt:best",
            name: "Best",
            sortOrder: 2,
            sevenDayLimitUsedPercent: 90,
            fiveHourLimitUsedPercent: 70
        )
        let lowerMinimum = makeSharedAccountRecord(
            identityKey: "chatgpt:lower",
            name: "Lower Minimum",
            sortOrder: 3,
            sevenDayLimitUsedPercent: 95,
            fiveHourLimitUsedPercent: 60
        )

        let selected = CodexSharedAccountSwitchService.bestRateLimitCandidate(
            in: [incomplete, balanced, best, lowerMinimum]
        )

        #expect(selected?.id == best.id)
    }

    @Test func sharedIntentResolverReturnsCurrentSelectedAndBestAccounts() throws {
        let current = makeSharedAccountRecord(
            identityKey: "chatgpt:current",
            name: "Current",
            sortOrder: 0,
            sevenDayLimitUsedPercent: 65,
            fiveHourLimitUsedPercent: 60
        )
        let selected = makeSharedAccountRecord(
            identityKey: "chatgpt:selected",
            name: "Selected",
            sortOrder: 1,
            sevenDayLimitUsedPercent: 70,
            fiveHourLimitUsedPercent: 70
        )
        let best = makeSharedAccountRecord(
            identityKey: "chatgpt:best",
            name: "Best",
            sortOrder: 2,
            sevenDayLimitUsedPercent: 95,
            fiveHourLimitUsedPercent: 80
        )
        let state = makeSharedState(
            currentAccountID: current.id,
            selectedAccountID: selected.id,
            selectedAccountIsLive: true,
            accounts: [current, selected, best]
        )

        #expect(try CodexSharedAccountIntentResolver.currentEntity(in: state).id == current.id)
        #expect(try CodexSharedAccountIntentResolver.selectedEntity(in: state).id == selected.id)
        #expect(try CodexSharedAccountIntentResolver.bestEntity(in: state).id == best.id)
    }

    @Test func sharedIntentResolverKeepsStrictSelectionSeparateFromFallbackSelection() throws {
        let current = makeSharedAccountRecord(
            identityKey: "chatgpt:current",
            name: "Current",
            sortOrder: 0,
            sevenDayLimitUsedPercent: 65,
            fiveHourLimitUsedPercent: 60
        )
        let selected = makeSharedAccountRecord(
            identityKey: "chatgpt:selected",
            name: "Selected",
            sortOrder: 1,
            sevenDayLimitUsedPercent: 70,
            fiveHourLimitUsedPercent: 70
        )
        let staleState = makeSharedState(
            currentAccountID: current.id,
            selectedAccountID: selected.id,
            selectedAccountIsLive: false,
            accounts: [current, selected]
        )

        #expect(throws: CodexSharedIntentLookupError.self) {
            try CodexSharedAccountIntentResolver.selectedEntity(in: staleState)
        }

        let resolution = try CodexSharedAccountIntentResolver.selectedOrCurrentEntityResolution(in: staleState)
        #expect(resolution.entity.id == current.id)
        #expect(resolution.usedCurrentFallback)
    }

    @Test func sharedIntentResolverRanksExactPrefixAndSubstringMatches() throws {
        let work = makeSharedAccountRecord(
            identityKey: "chatgpt:work",
            name: "Work",
            emailHint: "work@example.com",
            accountIdentifier: "acct-work",
            sortOrder: 0,
            sevenDayLimitUsedPercent: 90,
            fiveHourLimitUsedPercent: 90
        )
        let workshop = makeSharedAccountRecord(
            identityKey: "chatgpt:workshop",
            name: "Workshop",
            emailHint: "team@example.com",
            accountIdentifier: "acct-workshop",
            sortOrder: 1,
            sevenDayLimitUsedPercent: 80,
            fiveHourLimitUsedPercent: 80
        )
        let night = makeSharedAccountRecord(
            identityKey: "chatgpt:night",
            name: "Late Night",
            emailHint: "night@example.com",
            accountIdentifier: "acct-night",
            sortOrder: 2,
            sevenDayLimitUsedPercent: 70,
            fiveHourLimitUsedPercent: 70
        )
        let state = makeSharedState(accounts: [workshop, night, work])

        let exactMatches = try CodexSharedAccountIntentResolver.matchingEntities(
            matching: "Work",
            in: state
        )
        #expect(exactMatches.map(\.id) == [work.id, workshop.id])
        #expect(
            try CodexSharedAccountIntentResolver.preferredEntity(matching: "work@example.com", in: state).id
                == work.id
        )
        #expect(
            try CodexSharedAccountIntentResolver.preferredEntity(matching: "night", in: state).id
                == night.id
        )
    }

    @Test func sharedIntentResolverRejectsMissingSelectionAndEmptySearch() {
        let account = makeSharedAccountRecord(
            identityKey: "chatgpt:only",
            name: "Only",
            sortOrder: 0,
            sevenDayLimitUsedPercent: 50,
            fiveHourLimitUsedPercent: 50
        )
        let state = makeSharedState(accounts: [account])

        #expect(throws: CodexSharedIntentLookupError.self) {
            try CodexSharedAccountIntentResolver.selectedEntity(in: state)
        }

        #expect(throws: CodexSharedIntentLookupError.self) {
            try CodexSharedAccountIntentResolver.matchingEntities(matching: "   ", in: state)
        }
    }

    @Test func accountEntityQueryReturnsEmptyCollectionsForNormalEmptyStates() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        let store = CodexSharedStateStore(baseURL: temporaryDirectory)
        let query = CodexAccountEntityQuery(store: store)

        try store.save(makeSharedState(accounts: []))
        let emptySuggestions = try await query.suggestedEntities()
        #expect(emptySuggestions.isEmpty)

        let account = makeSharedAccountRecord(
            identityKey: "chatgpt:only",
            name: "Only",
            sortOrder: 0,
            sevenDayLimitUsedPercent: 50,
            fiveHourLimitUsedPercent: 50
        )
        try store.save(makeSharedState(accounts: [account]))

        let emptySearchMatches = try await query.entities(matching: "   ")
        let missingMatches = try await query.entities(matching: "missing")
        #expect(emptySearchMatches.isEmpty)
        #expect(missingMatches.isEmpty)
    }

    @Test func restoreSortPreferencesUsesStoredValuesAndFallsBackSafely() {
        let controller = makeController(
            authFileManager: FakeAuthFileManager(contents: makeChatGPTAuthJSON(accountID: "acct-123"))
        )

        controller.restoreSortPreferences(
            sortCriterionRawValue: AccountSortCriterion.rateLimit.rawValue,
            sortDirectionRawValue: SortDirection.descending.rawValue
        )
        #expect(controller.sortCriterion == .rateLimit)
        #expect(controller.sortDirection == .descending)

        controller.restoreSortPreferences(
            sortCriterionRawValue: "not-a-real-criterion",
            sortDirectionRawValue: "not-a-real-direction"
        )
        #expect(controller.sortCriterion == .dateAdded)
        #expect(controller.sortDirection == .ascending)
    }

    @Test func notificationAuthorizationRequestsAreForwardedThroughController() async {
        let notificationManager = FakeNotificationManager()
        notificationManager.authorizationRequestResult = .denied
        let controller = makeController(
            authFileManager: FakeAuthFileManager(contents: makeChatGPTAuthJSON(accountID: "acct-123")),
            notificationManager: notificationManager
        )

        let result = await controller.requestNotificationAuthorizationForSettings()

        #expect(result == .denied)
    }

    @Test func sharedStateOnlyPublishesSelectedAccountWhileSelectionContextIsPresented() async throws {
        let container = try makeInMemoryContainer()
        let controller = makeController(
            authFileManager: FakeAuthFileManager(contents: makeChatGPTAuthJSON(accountID: "acct-selected"))
        )

        controller.configure(modelContext: container.mainContext, undoManager: nil)
        await controller.captureCurrentAccountNow()
        let selectedAccount = try #require(fetchAccounts(in: container.mainContext).first)

        controller.setPrimarySelectionContextPresented(true)
        let liveState = try controller.sharedStateForTesting()
        #expect(liveState.selectedAccountID == selectedAccount.identityKey)
        #expect(liveState.selectedAccount?.id == selectedAccount.identityKey)

        controller.setPrimarySelectionContextPresented(false)
        let hiddenState = try controller.sharedStateForTesting()
        #expect(hiddenState.selectedAccountID == nil)
        #expect(hiddenState.selectedAccount == nil)
    }

    @Test func sharedStateUsesLocalSnapshotAvailabilityInsteadOfSyncedModelFlag() async throws {
        let container = try makeInMemoryContainer()
        let snapshotAvailabilityStore = LocalAccountSnapshotAvailabilityStore(
            baseURL: try makeTemporaryDirectory()
        )
        let controller = makeController(
            authFileManager: FakeAuthFileManager(contents: makeChatGPTAuthJSON(accountID: "acct-local-availability")),
            snapshotAvailabilityStore: snapshotAvailabilityStore
        )

        controller.configure(modelContext: container.mainContext, undoManager: nil)

        let account = StoredAccount(
            identityKey: "identity-local",
            name: "Local Only",
            customOrder: 0,
            hasLocalSnapshot: false,
            authModeRaw: "chatgpt"
        )
        container.mainContext.insert(account)
        try container.mainContext.save()

        snapshotAvailabilityStore.setSnapshotAvailable(true, forIdentityKey: account.identityKey)

        let sharedState = try controller.sharedStateForTesting()
        let sharedAccount = try #require(sharedState.accounts.first)
        #expect(sharedAccount.hasLocalSnapshot)
    }

    @Test func sharedStateSuppressesStaleSyncedSnapshotAvailability() async throws {
        let container = try makeInMemoryContainer()
        let snapshotAvailabilityStore = LocalAccountSnapshotAvailabilityStore(
            baseURL: try makeTemporaryDirectory()
        )
        let controller = makeController(
            authFileManager: FakeAuthFileManager(contents: makeChatGPTAuthJSON(accountID: "acct-stale-availability")),
            snapshotAvailabilityStore: snapshotAvailabilityStore
        )

        controller.configure(modelContext: container.mainContext, undoManager: nil)

        let account = StoredAccount(
            identityKey: "identity-stale",
            name: "Stale Availability",
            customOrder: 0,
            hasLocalSnapshot: true,
            authModeRaw: "chatgpt"
        )
        container.mainContext.insert(account)
        try container.mainContext.save()

        snapshotAvailabilityStore.setSnapshotAvailable(false, forIdentityKey: account.identityKey)

        let sharedState = try controller.sharedStateForTesting()
        let sharedAccount = try #require(sharedState.accounts.first)
        #expect(sharedAccount.hasLocalSnapshot == false)
    }

    @Test func legacySyncedLocalSnapshotFlagIsNormalizedBeforeCloudSync() throws {
        let container = try makeInMemoryContainer()
        let account = StoredAccount(
            identityKey: "identity-legacy-availability",
            name: "Legacy Availability",
            customOrder: 0,
            hasLocalSnapshot: true,
            authModeRaw: "chatgpt"
        )
        container.mainContext.insert(account)
        try container.mainContext.save()

        let didChange = try StoredAccountLegacyCloudSyncRepair.normalizeLocalOnlyFieldsIfNeeded(
            in: container.mainContext
        )

        #expect(didChange)
        let refreshedAccount = try #require(fetchAccounts(in: container.mainContext).first)
        #expect(refreshedAccount.hasLocalSnapshot == false)
    }

    @Test func queuedSharedCommandsAreAcknowledgedOnlyAfterHandling() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        let queue = CodexSharedAppCommandQueue(baseURL: temporaryDirectory)
        try queue.enqueue(CodexSharedAppCommand(action: .captureCurrentAccount))

        let container = try makeInMemoryContainer()
        let controller = makeController(
            authFileManager: FakeAuthFileManager(contents: makeChatGPTAuthJSON(accountID: "acct-queued"))
        )

        controller.configure(modelContext: container.mainContext, undoManager: nil)
        await controller.processPendingSharedCommands(
            allowsUnitTestExecution: true,
            queue: queue
        )

        let accounts = try fetchAccounts(in: container.mainContext)
        #expect(accounts.count == 1)
        let remainingCommands = try queue.load()
        #expect(remainingCommands.isEmpty)
    }

    @Test func expectedResultCommandsPersistSuccessfulCompletions() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        let queue = CodexSharedAppCommandQueue(baseURL: temporaryDirectory)
        let resultStore = CodexSharedAppCommandResultStore(baseURL: temporaryDirectory)
        let authContents = makeChatGPTAuthJSON(accountID: "acct-expected-result")
        let expectedIdentityKey = try CodexAuthFile.parse(contents: authContents).identityKey
        let queuedCommand = CodexSharedAppCommand(
            action: .captureCurrentAccount,
            expectsResult: true
        )
        try queue.enqueue(queuedCommand)

        let container = try makeInMemoryContainer()
        let controller = makeController(
            authFileManager: FakeAuthFileManager(contents: authContents)
        )

        controller.configure(modelContext: container.mainContext, undoManager: nil)
        await controller.processPendingSharedCommands(
            allowsUnitTestExecution: true,
            queue: queue,
            resultStore: resultStore
        )

        let result = try #require(try resultStore.load(commandID: queuedCommand.id))
        #expect(result.status == .success)
        #expect(result.accountIdentityKey == expectedIdentityKey)
        #expect(try queue.load().isEmpty)
    }

    @Test func failedSharedCommandsStayQueuedForRetry() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        let queue = CodexSharedAppCommandQueue(baseURL: temporaryDirectory)
        let queuedCommand = CodexSharedAppCommand(action: .captureCurrentAccount)
        try queue.enqueue(queuedCommand)

        let container = try makeInMemoryContainer()
        let authFileManager = FakeAuthFileManager(contents: makeChatGPTAuthJSON(accountID: "acct-failed"))
        await authFileManager.clearLinkedLocation()
        let controller = makeController(authFileManager: authFileManager)

        controller.configure(modelContext: container.mainContext, undoManager: nil)
        await controller.processPendingSharedCommands(
            allowsUnitTestExecution: true,
            queue: queue
        )

        let accounts = try fetchAccounts(in: container.mainContext)
        #expect(accounts.isEmpty)
        #expect(try queue.load() == [queuedCommand])
    }

    @Test func expectedResultCommandsAcknowledgeFailuresAndStoreErrorResults() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        let queue = CodexSharedAppCommandQueue(baseURL: temporaryDirectory)
        let resultStore = CodexSharedAppCommandResultStore(baseURL: temporaryDirectory)
        let queuedCommand = CodexSharedAppCommand(
            action: .captureCurrentAccount,
            expectsResult: true
        )
        try queue.enqueue(queuedCommand)

        let container = try makeInMemoryContainer()
        let authFileManager = FakeAuthFileManager(contents: makeChatGPTAuthJSON(accountID: "acct-failed-result"))
        await authFileManager.clearLinkedLocation()
        let controller = makeController(authFileManager: authFileManager)

        controller.configure(modelContext: container.mainContext, undoManager: nil)
        await controller.processPendingSharedCommands(
            allowsUnitTestExecution: true,
            queue: queue,
            resultStore: resultStore
        )

        let result = try #require(try resultStore.load(commandID: queuedCommand.id))
        #expect(result.status == .failure)
        #expect(try queue.load().isEmpty)
    }

    @Test func sharedCommandProcessingRepeatsWhenNewCommandsArriveMidPass() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        let queue = CodexSharedAppCommandQueue(baseURL: temporaryDirectory)

        let container = try makeInMemoryContainer()
        let authFileManager = ReentrantQueueingAuthFileManager(
            initialContents: makeChatGPTAuthJSON(accountID: "acct-first"),
            queuedContents: makeChatGPTAuthJSON(accountID: "acct-second"),
            queue: queue
        )
        let controller = makeController(authFileManager: authFileManager)

        controller.configure(modelContext: container.mainContext, undoManager: nil)
        authFileManager.controller = controller
        await controller.refreshAuthStateForTesting()
        authFileManager.enableQueuedCommandOnNextRead()
        try queue.enqueue(CodexSharedAppCommand(action: .captureCurrentAccount))

        await controller.processPendingSharedCommands(
            allowsUnitTestExecution: true,
            queue: queue
        )

        try await waitUntil(iterations: 200, sleepMilliseconds: 5) {
            let accountCount = await MainActor.run {
                (try? fetchAccounts(in: container.mainContext).count) ?? 0
            }
            let isQueueEmpty = (try? queue.load().isEmpty) == true
            return accountCount == 2 && isQueueEmpty
        }
    }

    @Test func quitCommandDrainsLoadedCommandsBeforeTerminating() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        let queue = CodexSharedAppCommandQueue(baseURL: temporaryDirectory)
        try queue.enqueue(CodexSharedAppCommand(action: .quitApplication))
        try queue.enqueue(CodexSharedAppCommand(action: .captureCurrentAccount))

        let container = try makeInMemoryContainer()
        let terminationRecorder = TerminationRecorder()
        let controller = makeController(
            authFileManager: FakeAuthFileManager(contents: makeChatGPTAuthJSON(accountID: "acct-after-quit")),
            terminateApplication: {
                Task {
                    await terminationRecorder.recordTermination()
                }
            }
        )

        controller.configure(modelContext: container.mainContext, undoManager: nil)
        await controller.processPendingSharedCommands(
            allowsUnitTestExecution: true,
            queue: queue
        )

        let accounts = try fetchAccounts(in: container.mainContext)
        #expect(accounts.count == 1)
        #expect(try queue.load().isEmpty)
        try await waitUntil {
            await terminationRecorder.terminationCount() == 1
        }
    }

    @Test func menuBarIconOptionResolvesUnknownStoredValueToDefault() {
        #expect(MenuBarIconOption.resolve(from: "arrow.left.arrow.right") == .switcher)
        #expect(MenuBarIconOption.resolve(from: "key.card.fill") == .keyCard)
        #expect(MenuBarIconOption.resolve(from: "not-a-real-symbol") == .defaultOption)
    }

    @Test func removeAllAccountsDeletesSavedAccountsAndSecrets() async throws {
        let container = try makeInMemoryContainer()
        let secretStore = FakeSecretStore()
        let syncedRateLimitCredentialStore = FakeSyncedRateLimitCredentialStore()
        let controller = makeController(
            authFileManager: FakeAuthFileManager(contents: makeChatGPTAuthJSON(accountID: "acct-123")),
            secretStore: secretStore,
            syncedRateLimitCredentialStore: syncedRateLimitCredentialStore
        )

        let firstAccount = makeStoredAccount(name: "Work", customOrder: 0, accountID: "acct-work")
        let secondAccount = makeStoredAccount(name: "Personal", customOrder: 1, accountID: "acct-personal")

        container.mainContext.insert(firstAccount)
        container.mainContext.insert(secondAccount)
        try container.mainContext.save()

        try await secretStore.saveSecret("work-secret", for: firstAccount.id)
        try await secretStore.saveSecret("personal-secret", for: secondAccount.id)
        try await syncedRateLimitCredentialStore.save(
            SyncedRateLimitCredential(
                credentials: CodexRateLimitCredentials(
                    identityKey: firstAccount.identityKey,
                    authMode: .chatgpt,
                    accountID: "acct-work",
                    accessToken: "token-work",
                    idToken: nil
                )
            )
        )
        try await syncedRateLimitCredentialStore.save(
            SyncedRateLimitCredential(
                credentials: CodexRateLimitCredentials(
                    identityKey: secondAccount.identityKey,
                    authMode: .chatgpt,
                    accountID: "acct-personal",
                    accessToken: "token-personal",
                    idToken: nil
                )
            )
        )

        controller.configure(modelContext: container.mainContext, undoManager: nil)
        await controller.removeAllAccountsNow()

        #expect(try fetchAccounts(in: container.mainContext).isEmpty)
        #expect(await secretStore.secret(forIdentityKey: firstAccount.identityKey) == nil)
        #expect(await secretStore.secret(forIdentityKey: secondAccount.identityKey) == nil)
        #expect(await syncedRateLimitCredentialStore.containsCredential(forIdentityKey: firstAccount.identityKey) == false)
        #expect(await syncedRateLimitCredentialStore.containsCredential(forIdentityKey: secondAccount.identityKey) == false)
    }

    @Test func removalShortcutSupportsDeleteWithExpectedModifiersOnly() {
        #expect(ContentView.supportsRemovalShortcut(modifiers: []) == true)
        #expect(ContentView.supportsRemovalShortcut(modifiers: [.command]) == true)
        #expect(ContentView.supportsRemovalShortcut(modifiers: [.shift]) == true)
        #expect(ContentView.supportsRemovalShortcut(modifiers: [.command, .shift]) == true)
        #expect(ContentView.supportsRemovalShortcut(modifiers: [.option]) == false)
        #expect(ContentView.supportsRemovalShortcut(modifiers: [.control]) == false)
        #expect(ContentView.supportsRemovalShortcut(modifiers: [.command, .option]) == false)
    }

    @Test func contextMenuTargetsClickedRowUnlessItBelongsToMultiSelection() {
        let first = UUID()
        let second = UUID()
        let third = UUID()

        #expect(
            ContentView.contextMenuTargetIDs(
                clickedAccountID: third,
                currentSelection: [first, second]
            ) == [third]
        )

        #expect(
            ContentView.contextMenuTargetIDs(
                clickedAccountID: second,
                currentSelection: [first, second]
            ) == [first, second]
        )

        #expect(
            ContentView.contextMenuTargetIDs(
                clickedAccountID: first,
                currentSelection: [first]
            ) == [first]
        )
    }

    @Test func spaceShortcutRequiresSingleSelectionAndNoRename() {
        #expect(ContentView.canSwitchSelectedAccountViaSpace(selectionCount: 1, isRenaming: false))
        #expect(!ContentView.canSwitchSelectedAccountViaSpace(selectionCount: 0, isRenaming: false))
        #expect(!ContentView.canSwitchSelectedAccountViaSpace(selectionCount: 2, isRenaming: false))
        #expect(!ContentView.canSwitchSelectedAccountViaSpace(selectionCount: 1, isRenaming: true))
    }

    @Test func lastLoginDescriptionUsesExpectedRelativeFormats() {
        let now = Date(timeIntervalSince1970: 1_000_000)

        #expect(AccountDisplayFormatter.lastLoginListDescription(from: nil, relativeTo: now) == "Last login: never")
        #expect(AccountDisplayFormatter.lastLoginListDescription(from: now.addingTimeInterval(-(59 * 60)), relativeTo: now) == "Last login: this hour")
        #expect(AccountDisplayFormatter.lastLoginListDescription(from: now.addingTimeInterval(-(1 * 60 * 60)), relativeTo: now) == "Last login: 1h ago")
        #expect(AccountDisplayFormatter.lastLoginListDescription(from: now.addingTimeInterval(-(10 * 60 * 60)), relativeTo: now) == "Last login: 10h ago")
        #expect(AccountDisplayFormatter.lastLoginListDescription(from: now.addingTimeInterval(-(24 * 60 * 60)), relativeTo: now) == "Last login: 1d ago")
        #expect(AccountDisplayFormatter.lastLoginListDescription(from: now.addingTimeInterval(-(7 * 24 * 60 * 60)), relativeTo: now) == "Last login: 7d ago")
        #expect(AccountDisplayFormatter.lastLoginListDescription(from: now.addingTimeInterval(-(3_432 * 24 * 60 * 60)), relativeTo: now) == "Last login: 3432d ago")
        #expect(AccountDisplayFormatter.lastLoginListDescription(from: now.addingTimeInterval(5 * 60), relativeTo: now) == "Last login: this hour")
    }

    @Test func accountMetadataDescriptionShowsKnownAndUnknownLimits() {
        let now = Date(timeIntervalSince1970: 1_000_000)

        #expect(
            AccountDisplayFormatter.listMetadataDescription(
                lastLoginAt: now.addingTimeInterval(-(3 * 60 * 60)),
                sevenDayRemainingPercent: 93,
                fiveHourRemainingPercent: 34,
                relativeTo: now
            ) == "Last login: 3h ago • 5h: 34% • 7d: 93%"
        )

        #expect(
            AccountDisplayFormatter.listMetadataDescription(
                lastLoginAt: nil,
                sevenDayRemainingPercent: nil,
                fiveHourRemainingPercent: nil,
                relativeTo: now
            ) == "Last login: never • 5h: ? • 7d: ?"
        )
    }

    @Test func usageLimitColorInterpolationMatchesRequestedScale() {
        let red = AccountDisplayFormatter.usageColorComponents(forRemainingPercent: 0)
        #expect(abs(red.red - 1) < 0.0001)
        #expect(abs(red.green) < 0.0001)
        #expect(abs(red.blue) < 0.0001)

        let orange = AccountDisplayFormatter.usageColorComponents(forRemainingPercent: 25)
        #expect(abs(orange.red - 1) < 0.0001)
        #expect(abs(orange.green - 0.19) < 0.0001)
        #expect(abs(orange.blue) < 0.0001)

        let mid = AccountDisplayFormatter.usageColorComponents(forRemainingPercent: 50)
        #expect(abs(mid.red - 1) < 0.0001)
        #expect(abs(mid.green - 0.38) < 0.0001)
        #expect(abs(mid.blue) < 0.0001)

        let yellowGreen = AccountDisplayFormatter.usageColorComponents(forRemainingPercent: 75)
        #expect(abs(yellowGreen.red - 0.5) < 0.0001)
        #expect(abs(yellowGreen.green - 0.69) < 0.0001)
        #expect(abs(yellowGreen.blue) < 0.0001)

        let green = AccountDisplayFormatter.usageColorComponents(forRemainingPercent: 100)
        #expect(abs(green.red) < 0.0001)
        #expect(abs(green.green - 1) < 0.0001)
        #expect(abs(green.blue) < 0.0001)
    }

    @Test func startupMigratesLegacyUsedPercentValuesToRemainingPercent() async throws {
        let container = try makeInMemoryContainer()
        let authFileManager = FakeAuthFileManager(contents: makeChatGPTAuthJSON(accountID: "acct-current"))
        await authFileManager.clearLinkedLocation()
        let controller = makeController(authFileManager: authFileManager)

        container.mainContext.insert(
            StoredAccount(
                identityKey: "chatgpt:acct-legacy",
                name: "Legacy",
                customOrder: 0,
                authModeRaw: "chatgpt",
                sevenDayLimitUsedPercent: 93,
                fiveHourLimitUsedPercent: 34,
                rateLimitDisplayVersion: nil
            )
        )
        try container.mainContext.save()

        controller.configure(modelContext: container.mainContext, undoManager: nil)
        await controller.refreshAuthStateForTesting()

        let migratedAccount = try #require(fetchAccounts(in: container.mainContext).first)
        #expect(migratedAccount.sevenDayLimitUsedPercent == 7)
        #expect(migratedAccount.fiveHourLimitUsedPercent == 66)
        #expect(migratedAccount.rateLimitDisplayVersion == 1)
    }

    @Test func sessionRateLimitReaderUsesNewestObservationFromRealCodexTokenCountEvents() async throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory.appending(path: "codex-switcher-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: rootURL) }
        let sessionsDirectoryURL = rootURL
            .appending(path: "sessions", directoryHint: .isDirectory)
            .appending(path: "2026", directoryHint: .isDirectory)
            .appending(path: "04", directoryHint: .isDirectory)
            .appending(path: "09", directoryHint: .isDirectory)

        try fileManager.createDirectory(at: sessionsDirectoryURL, withIntermediateDirectories: true)

        let sessionFileURL = sessionsDirectoryURL.appending(path: "rollout-test.jsonl", directoryHint: .notDirectory)
        try makeSessionRateLimitJSONL([
            (timestamp: "1970-01-01T00:32:00.000Z", fiveHourPercent: 12, sevenDayPercent: 88),
            (timestamp: "1970-01-01T00:34:00.000Z", fiveHourPercent: 34, sevenDayPercent: 93),
        ], shape: .payloadRateLimits, fiveHourWindowMinutes: 299, sevenDayWindowMinutes: 10_079)
        .write(to: sessionFileURL, atomically: true, encoding: .utf8)

        let observation = await CodexSessionRateLimitReader().readLatestObservation(in: rootURL)

        #expect(observation?.fiveHourRemainingPercent == 66)
        #expect(observation?.sevenDayRemainingPercent == 7)
    }

    @Test func remoteRateLimitProviderUsesUsageAPIForSavedAccounts() async throws {
        let rawContents = makeChatGPTAuthJSON(
            accountID: "acct-remote",
            subject: "auth0|acct-remote",
            email: "remote@example.com"
        )
        let identityKey = try CodexAuthFile.parse(contents: rawContents).identityKey
        let accessToken = try CodexAuthFile.parseRateLimitCredentials(contents: rawContents).accessToken ?? ""
        let fiveHourReset = Int(Date().addingTimeInterval(3_600).timeIntervalSince1970)
        let sevenDayReset = Int(Date().addingTimeInterval(86_400).timeIntervalSince1970)
        MockURLProtocol.lastRequest = nil

        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.lastRequest = request

            let body = """
            {
              "rate_limit": {
                "limit_id": "codex",
                "primary_window": {
                  "used_percent": 34,
                  "limit_window_seconds": 17940,
                  "reset_at": \(fiveHourReset)
                },
                "secondary_window": {
                  "used_percent": 93,
                  "limit_window_seconds": 604740,
                  "reset_at": \(sevenDayReset)
                }
              }
            }
            """
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(body.utf8))
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let urlSession = URLSession(configuration: configuration)
        let provider = CodexRateLimitProvider(
            requestLimiter: CodexRateLimitRequestLimiter(maxRequestsPerMinute: 60, minimumSpacing: 0),
            urlSession: urlSession
        )

        let outcome = await provider.fetchSnapshot(
            for: CodexRateLimitRequest(
                identityKey: identityKey,
                credentials: try CodexAuthFile.parseRateLimitCredentials(contents: rawContents),
                linkedLocation: nil,
                isCurrentAccount: false
            )
        )

        #expect(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer \(accessToken)")
        #expect(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "acct-remote")
        #expect(outcome.remoteFailure == nil)
        let snapshot = try #require(outcome.snapshot)

        #expect(snapshot.source == .remoteUsageAPI)
        #expect(snapshot.fiveHourRemainingPercent == 66)
        #expect(snapshot.sevenDayRemainingPercent == 7)
        #expect(snapshot.fiveHourResetsAt == Date(timeIntervalSince1970: TimeInterval(fiveHourReset)))
        #expect(snapshot.sevenDayResetsAt == Date(timeIntervalSince1970: TimeInterval(sevenDayReset)))
    }

    @Test func iconCatalogOffersExpandedChoicesAndKeepsKeyDefault() throws {
        #expect(AccountIconOption.allCases.count >= 70)
        #expect(AccountIconOption.defaultOption == .key)
        #expect(AccountIconOption.resolve(from: "not-a-real-symbol") == .key)
        #expect(AccountIconOption.displayOrder.count == AccountIconOption.allCases.count)
        #expect(Set(AccountIconOption.displayOrder).count == AccountIconOption.allCases.count)
        #expect(
            Array(AccountIconOption.displayOrder.prefix(7))
                == [
                    .key,
                    .star,
                    .heart,
                    .house,
                    .briefcase,
                    .graduationCap,
                    .hammer,
                ]
        )
        let hammerIndex = try #require(AccountIconOption.displayOrder.firstIndex(of: .hammer))
        #expect(
            Array(AccountIconOption.displayOrder[(hammerIndex + 1)...(hammerIndex + 7)])
                == [.building, .columns, .person, .personSquare, .personBadgeKey, .people, .profile]
        )
    }

    @Test func iconCatalogUsesOnlySymbolsAvailableOnMacOS() {
        let unavailableSymbols = AccountIconOption.allCases.compactMap { option in
            NSImage(systemSymbolName: option.systemName, accessibilityDescription: nil) == nil
                ? option.systemName
                : nil
        }

        #expect(unavailableSymbols.isEmpty)
    }

    @Test func startupReconcilesDuplicateAccountsForTheSameIdentityKey() async throws {
        let container = try makeInMemoryContainer()
        let secretStore = FakeSecretStore()
        let controller = makeController(
            authFileManager: FakeAuthFileManager(contents: makeChatGPTAuthJSON(accountID: "acct-current")),
            secretStore: secretStore
        )

        let duplicateContents = makeChatGPTAuthJSON(accountID: "acct-duplicate")
        let snapshot = try CodexAuthFile.parse(contents: duplicateContents)

        container.mainContext.insert(
            StoredAccount(
                identityKey: snapshot.identityKey,
                name: "Account 7",
                createdAt: .now,
                customOrder: 7,
                authFileContents: duplicateContents,
                authModeRaw: snapshot.authMode.rawValue,
                emailHint: snapshot.email,
                accountIdentifier: snapshot.accountIdentifier
            )
        )
        container.mainContext.insert(
            StoredAccount(
                identityKey: snapshot.identityKey,
                name: "Work",
                createdAt: .distantPast,
                lastLoginAt: .now,
                customOrder: 0,
                authFileContents: duplicateContents,
                authModeRaw: snapshot.authMode.rawValue,
                emailHint: snapshot.email,
                accountIdentifier: snapshot.accountIdentifier,
                iconSystemName: AccountIconOption.briefcase.systemName
            )
        )
        try container.mainContext.save()

        controller.configure(modelContext: container.mainContext, undoManager: nil)
        await controller.refreshAuthStateForTesting()

        let accounts = try fetchAccounts(in: container.mainContext)
        let reconciledAccount = try #require(accounts.first)

        #expect(accounts.count == 1)
        #expect(reconciledAccount.name == "Work")
        #expect(reconciledAccount.lastLoginAt != nil)
        #expect(reconciledAccount.customOrder == 0)
        #expect(reconciledAccount.iconSystemName == AccountIconOption.briefcase.systemName)
        #expect(reconciledAccount.authFileContents == nil)
        #expect(reconciledAccount.hasLocalSnapshot == false)
        #expect(await secretStore.secret(forIdentityKey: snapshot.identityKey) == duplicateContents)
    }
}

@MainActor
private func makeController(
    authFileManager: any AuthFileManaging,
    snapshotAvailabilityStore: LocalAccountSnapshotAvailabilityStore? = nil,
    secretStore: FakeSecretStore? = nil,
    syncedRateLimitCredentialStore: FakeSyncedRateLimitCredentialStore = FakeSyncedRateLimitCredentialStore(),
    notificationManager: FakeNotificationManager = FakeNotificationManager(),
    rateLimitProvider: CodexRateLimitProviding = FakeRateLimitProvider(),
    lowPowerModeProvider: @escaping () -> Bool = { false },
    batteryChargePercentProvider: @escaping () -> Int? = { nil },
    terminateApplication: @escaping () -> Void = {},
    autopilotEnabled: Bool = false
) -> AppController {
    let resolvedSnapshotAvailabilityStore = snapshotAvailabilityStore ?? LocalAccountSnapshotAvailabilityStore(
        baseURL: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
    )
    let resolvedSecretStore = secretStore ?? FakeSecretStore(
        snapshotAvailabilityStore: resolvedSnapshotAvailabilityStore
    )
    resolvedSecretStore.attachSnapshotAvailabilityStore(resolvedSnapshotAvailabilityStore)

    return AppController(
        authFileManager: authFileManager,
        secretStore: resolvedSecretStore,
        snapshotAvailabilityStore: resolvedSnapshotAvailabilityStore,
        syncedRateLimitCredentialStore: syncedRateLimitCredentialStore,
        notificationManager: notificationManager,
        rateLimitProvider: rateLimitProvider,
        lowPowerModeProvider: lowPowerModeProvider,
        batteryChargePercentProvider: batteryChargePercentProvider,
        terminateApplication: terminateApplication,
        autopilotEnabled: autopilotEnabled
    )
}

private func makeInMemoryContainer() throws -> ModelContainer {
    let schema = Schema([StoredAccount.self])
    let configuration = ModelConfiguration(
        "TestAccounts-\(UUID().uuidString)",
        schema: schema,
        isStoredInMemoryOnly: true,
        cloudKitDatabase: .none
    )
    return try ModelContainer(for: schema, configurations: [configuration])
}

private func fetchAccounts(in modelContext: ModelContext) throws -> [StoredAccount] {
    try modelContext.fetch(FetchDescriptor<StoredAccount>())
}

private func makeSharedAccountRecord(
    identityKey: String,
    name: String,
    emailHint: String? = nil,
    accountIdentifier: String? = nil,
    sortOrder: Double,
    sevenDayLimitUsedPercent: Int?,
    fiveHourLimitUsedPercent: Int?,
    hasLocalSnapshot: Bool = true
) -> SharedCodexAccountRecord {
    SharedCodexAccountRecord(
        id: identityKey,
        name: name,
        iconSystemName: "key.fill",
        emailHint: emailHint,
        accountIdentifier: accountIdentifier,
        authModeRaw: "chatgpt",
        lastLoginAt: nil,
        sevenDayLimitUsedPercent: sevenDayLimitUsedPercent,
        fiveHourLimitUsedPercent: fiveHourLimitUsedPercent,
        sevenDayResetsAt: nil,
        fiveHourResetsAt: nil,
        sevenDayDataStatusRaw: sevenDayLimitUsedPercent == nil
            ? RateLimitMetricDataStatus.missing.rawValue
            : RateLimitMetricDataStatus.exact.rawValue,
        fiveHourDataStatusRaw: fiveHourLimitUsedPercent == nil
            ? RateLimitMetricDataStatus.missing.rawValue
            : RateLimitMetricDataStatus.exact.rawValue,
        rateLimitsObservedAt: nil,
        sortOrder: sortOrder,
        hasLocalSnapshot: hasLocalSnapshot
    )
}

private func makeSharedState(
    currentAccountID: String? = nil,
    selectedAccountID: String? = nil,
    selectedAccountIsLive: Bool? = nil,
    accounts: [SharedCodexAccountRecord]
) -> SharedCodexState {
    SharedCodexState(
        schemaVersion: SharedCodexState.currentSchemaVersion,
        authState: .ready,
        linkedFolderPath: "/tmp/.codex",
        currentAccountID: currentAccountID,
        selectedAccountID: selectedAccountID,
        selectedAccountIsLive: selectedAccountIsLive ?? (selectedAccountID != nil),
        accounts: accounts,
        updatedAt: .now
    )
}

private func makeTemporaryDirectory() throws -> URL {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("CodexSwitcherTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    return directoryURL
}

private func makeChatGPTAuthJSON(
    accountID: String,
    userID: String? = nil,
    subject: String? = nil,
    email: String? = nil,
    workspaceID: String? = nil
) -> String {
    var authClaims: [String: Any] = [
        "chatgpt_account_id": accountID,
        "chatgpt_user_id": userID ?? "user-\(accountID)",
    ]
    if let workspaceID {
        authClaims["chatgpt_workspace_id"] = workspaceID
    }

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

    let idToken = makeJWT(idTokenPayload)
    let accessToken = makeJWT(accessTokenPayload)

    return """
    {
      "auth_mode": "chatgpt",
      "tokens": {
        "account_id": "\(accountID)",
        "id_token": "\(idToken)",
        "access_token": "\(accessToken)",
        "refresh_token": "refresh-\(accountID)"
      }
    }
    """
}

@MainActor
private func makeStoredAccount(name: String, customOrder: Double, accountID: String) -> StoredAccount {
    let contents = makeChatGPTAuthJSON(accountID: accountID)
    let snapshot = try! CodexAuthFile.parse(contents: contents)

    return StoredAccount(
        identityKey: snapshot.identityKey,
        name: name,
        customOrder: customOrder,
        authModeRaw: snapshot.authMode.rawValue,
        emailHint: snapshot.email,
        accountIdentifier: snapshot.accountIdentifier
    )
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

private func makeRateLimitSnapshot(
    identityKey: String,
    observedAt: Date = .now,
    fetchedAt: Date = .now,
    sevenDayRemainingPercent: Int = 93,
    fiveHourRemainingPercent: Int = 34
) -> CodexRateLimitSnapshot {
    CodexRateLimitSnapshot(
        identityKey: identityKey,
        observedAt: observedAt,
        fetchedAt: fetchedAt,
        source: .remoteUsageAPI,
        sevenDayRemainingPercent: sevenDayRemainingPercent,
        fiveHourRemainingPercent: fiveHourRemainingPercent,
        sevenDayResetsAt: observedAt.addingTimeInterval(7 * 24 * 60 * 60),
        fiveHourResetsAt: observedAt.addingTimeInterval(5 * 60 * 60)
    )
}

private struct TestPowerStateSource {
    var lowPowerModeEnabled: Bool
    var batteryChargePercent: Int?
}

private struct TestTimeoutError: Error {}

private func waitUntil(
    iterations: Int = 400,
    sleepMilliseconds: UInt64 = 0,
    condition: @escaping @Sendable () async -> Bool
) async throws {
    for _ in 0..<iterations {
        if await condition() {
            return
        }

        if sleepMilliseconds == 0 {
            await Task.yield()
        } else {
            try? await Task.sleep(nanoseconds: sleepMilliseconds * 1_000_000)
        }
    }

    throw TestTimeoutError()
}

private enum SessionRateLimitPayloadShape {
    case infoRateLimits
    case payloadRateLimits
}

private func makeSessionRateLimitJSONL(
    _ events: [(timestamp: String, fiveHourPercent: Int, sevenDayPercent: Int)],
    shape: SessionRateLimitPayloadShape = .infoRateLimits,
    fiveHourWindowMinutes: Int = 300,
    sevenDayWindowMinutes: Int = 10_080
) -> String {
    events.map { event in
        switch shape {
        case .infoRateLimits:
            """
            {"timestamp":"\(event.timestamp)","type":"event_msg","payload":{"type":"token_count","info":{"rate_limits":{"primary":{"used_percent":\(event.fiveHourPercent),"window_minutes":\(fiveHourWindowMinutes)},"secondary":{"used_percent":\(event.sevenDayPercent),"window_minutes":\(sevenDayWindowMinutes)}}}}}
            """
        case .payloadRateLimits:
            """
            {"timestamp":"\(event.timestamp)","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":\(event.fiveHourPercent),"window_minutes":\(fiveHourWindowMinutes)},"secondary":{"used_percent":\(event.sevenDayPercent),"window_minutes":\(sevenDayWindowMinutes)}}}}
            """
        }
    }.joined(separator: "\n")
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: @Sendable (URLRequest) throws -> (HTTPURLResponse, Data) = { _ in
        throw URLError(.badServerResponse)
    }
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            let (response, data) = try Self.requestHandler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

actor FakeAuthFileManager: AuthFileManaging {
    private(set) var currentContents: String
    private(set) var writeCallCount = 0
    private var linkedLocationValue: AuthLinkedLocation?
    private var readError: Error?
    private var writeError: Error?
    private var linkError: Error?
    private var isMissingAuthFile = false
    private var onChange: (@Sendable () -> Void)?

    init(
        contents: String,
        linkedLocation: AuthLinkedLocation = AuthLinkedLocation(
            folderURL: URL(fileURLWithPath: "/tmp/.codex", isDirectory: true),
            credentialStoreHint: .file
        ),
        readError: Error? = nil,
        writeError: Error? = nil,
        linkError: Error? = nil
    ) {
        self.currentContents = contents
        self.linkedLocationValue = linkedLocation
        self.readError = readError
        self.writeError = writeError
        self.linkError = linkError
    }

    func linkedLocation() async throws -> AuthLinkedLocation? {
        linkedLocationValue
    }

    func linkLocation(_ selectedURL: URL) async throws -> AuthLinkedLocation {
        if let linkError {
            throw linkError
        }

        let folderURL = selectedURL.hasDirectoryPath
            ? selectedURL
            : selectedURL.deletingLastPathComponent()
        let location = AuthLinkedLocation(folderURL: folderURL, credentialStoreHint: .file)
        linkedLocationValue = location
        return location
    }

    func clearLinkedLocation() async {
        linkedLocationValue = nil
    }

    func readAuthFile() async throws -> AuthFileReadResult {
        let currentContents = self.currentContents

        if let readError {
            throw readError
        }

        guard let linkedLocationValue else {
            throw AuthFileAccessError.accessRequired
        }

        if isMissingAuthFile {
            throw AuthFileAccessError.missingAuthFile(
                linkedLocationValue.authFileURL,
                credentialStoreHint: linkedLocationValue.credentialStoreHint
            )
        }

        return AuthFileReadResult(url: linkedLocationValue.authFileURL, contents: currentContents)
    }

    func writeAuthFile(_ contents: String) async throws {
        if let writeError {
            throw writeError
        }

        guard linkedLocationValue != nil else {
            throw AuthFileAccessError.accessRequired
        }

        writeCallCount += 1
        currentContents = contents
        isMissingAuthFile = false
    }

    func startMonitoring(_ onChange: @escaping @Sendable () -> Void) async {
        self.onChange = onChange
    }

    func setContents(_ contents: String) async {
        self.currentContents = contents
        self.isMissingAuthFile = false
    }

    func setMissingAuthFile(_ isMissingAuthFile: Bool) async {
        self.isMissingAuthFile = isMissingAuthFile
    }

    func simulateExternalChange(to contents: String) async {
        currentContents = contents
        isMissingAuthFile = false
        onChange?()
    }
}

final class FakeSecretStore: @unchecked Sendable, AccountSnapshotStoring {
    private let lock = NSLock()
    private var snapshotAvailabilityStore: LocalAccountSnapshotAvailabilityStore?
    private var snapshots: [String: String] = [:]
    private var legacySecrets: [UUID: String] = [:]
    private var saveError: Error?
    private var loadError: Error?
    private var deleteError: Error?
    private(set) var saveCallCount = 0

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

            saveCallCount += 1
            snapshots[identityKey] = contents
        }
        snapshotAvailabilityStore?.setSnapshotAvailable(true, forIdentityKey: identityKey)
    }

    func loadSnapshot(forIdentityKey identityKey: String) async throws -> String {
        try withLock {
            if let loadError {
                throw loadError
            }

            guard let snapshot = snapshots[identityKey] else {
                throw AccountSnapshotStoreError.missingSnapshot
            }

            return snapshot
        }
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

            guard snapshots[identityKey] == nil, let legacySnapshot = legacySecrets[accountID] else {
                legacySecrets.removeValue(forKey: accountID)
                return false
            }

            saveCallCount += 1
            snapshots[identityKey] = legacySnapshot
            legacySecrets.removeValue(forKey: accountID)
            return true
        }

        if didMigrate {
            snapshotAvailabilityStore?.setSnapshotAvailable(true, forIdentityKey: identityKey)
        }

        return didMigrate
    }

    func saveSecret(_ contents: String, for accountID: UUID) async throws {
        try withLock {
            if let saveError {
                throw saveError
            }

            legacySecrets[accountID] = contents
        }
    }

    func secret(forIdentityKey identityKey: String) async -> String? {
        withLock {
            snapshots[identityKey]
        }
    }

    func resetSaveCallCount() async {
        withLock {
            saveCallCount = 0
        }
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

actor FakeRateLimitProvider: CodexRateLimitProviding {
    private var results: [String: CodexRateLimitFetchResult] = [:]
    private var capturedIdentityKeys: [String] = []

    func fetchSnapshot(for request: CodexRateLimitRequest) async -> CodexRateLimitFetchResult {
        let identityKey = request.identityKey
        capturedIdentityKeys.append(identityKey)
        return results[identityKey] ?? CodexRateLimitFetchResult(remoteFailure: .missingCredentials)
    }

    func setSnapshot(_ snapshot: CodexRateLimitSnapshot, for identityKey: String) {
        results[identityKey] = CodexRateLimitFetchResult(snapshot: snapshot)
    }

    func setFailure(_ failure: CodexRateLimitFetchFailure, for identityKey: String) {
        results[identityKey] = CodexRateLimitFetchResult(remoteFailure: failure)
    }

    func requestCount(for identityKey: String) -> Int {
        capturedIdentityKeys.filter { $0 == identityKey }.count
    }

    func requestedIdentityKeys() -> [String] {
        capturedIdentityKeys
    }

    func resetRequests() {
        capturedIdentityKeys.removeAll()
    }
}

final class FakeSyncedRateLimitCredentialStore: @unchecked Sendable, SyncedRateLimitCredentialStoring {
    private let lock = NSLock()
    private var credentialsByIdentityKey: [String: SyncedRateLimitCredential] = [:]
    private var saveCount = 0

    func save(_ credential: SyncedRateLimitCredential) async throws {
        withLock {
            saveCount += 1
            credentialsByIdentityKey[credential.identityKey] = credential
        }
    }

    func load(forIdentityKey identityKey: String) async throws -> SyncedRateLimitCredential {
        try withLock {
            guard let credential = credentialsByIdentityKey[identityKey] else {
                throw SyncedRateLimitCredentialStoreError.missingCredential
            }

            return credential
        }
    }

    func delete(forIdentityKey identityKey: String) async throws {
        _ = withLock {
            credentialsByIdentityKey.removeValue(forKey: identityKey)
        }
    }

    func containsCredential(forIdentityKey identityKey: String) async -> Bool {
        withLock {
            credentialsByIdentityKey[identityKey] != nil
        }
    }

    func credential(forIdentityKey identityKey: String) async -> SyncedRateLimitCredential? {
        withLock {
            credentialsByIdentityKey[identityKey]
        }
    }

    func saveCallCount() async -> Int {
        withLock {
            saveCount
        }
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

@MainActor
final class FakeNotificationManager: AccountSwitchNotifying {
    private(set) var postedAccountNames: [String] = []
    var authorizationRequestResult: NotificationAuthorizationRequestResult = .enabled

    func postSwitchNotification(for accountName: String, kind: CodexSwitchNotificationKind) async {
        postedAccountNames.append(accountName)
    }

    func requestAuthorizationForNotificationsPreference() async -> NotificationAuthorizationRequestResult {
        authorizationRequestResult
    }
}

actor TerminationRecorder {
    private var count = 0

    func recordTermination() {
        count += 1
    }

    func terminationCount() -> Int {
        count
    }
}

@MainActor
final class ReentrantQueueingAuthFileManager: AuthFileManaging {
    weak var controller: AppController?

    private let initialContents: String
    private var currentContents: String
    private let queuedContents: String
    private let queue: CodexSharedAppCommandQueue
    private var linkedLocationValue: AuthLinkedLocation?
    private var hasQueuedAdditionalCommand = false
    private var shouldQueueAdditionalCommandOnNextRead = false
    private var onChange: (@Sendable () -> Void)?

    init(
        initialContents: String,
        queuedContents: String,
        queue: CodexSharedAppCommandQueue,
        linkedLocation: AuthLinkedLocation = AuthLinkedLocation(
            folderURL: URL(fileURLWithPath: "/tmp/.codex", isDirectory: true),
            credentialStoreHint: .file
        )
    ) {
        self.initialContents = initialContents
        self.currentContents = initialContents
        self.queuedContents = queuedContents
        self.queue = queue
        self.linkedLocationValue = linkedLocation
    }

    func linkedLocation() async throws -> AuthLinkedLocation? {
        linkedLocationValue
    }

    func linkLocation(_ selectedURL: URL) async throws -> AuthLinkedLocation {
        let folderURL = selectedURL.hasDirectoryPath
            ? selectedURL
            : selectedURL.deletingLastPathComponent()
        let location = AuthLinkedLocation(folderURL: folderURL, credentialStoreHint: .file)
        linkedLocationValue = location
        return location
    }

    func clearLinkedLocation() async {
        linkedLocationValue = nil
    }

    func readAuthFile() async throws -> AuthFileReadResult {
        guard let linkedLocationValue else {
            throw AuthFileAccessError.accessRequired
        }

        let currentContents = self.currentContents
        if shouldQueueAdditionalCommandOnNextRead && !hasQueuedAdditionalCommand {
            hasQueuedAdditionalCommand = true
            shouldQueueAdditionalCommandOnNextRead = false
            self.currentContents = queuedContents
            try? queue.enqueue(CodexSharedAppCommand(action: .captureCurrentAccount))
            if let controller {
                controller.requestPendingSharedCommandsProcessing(
                    allowsUnitTestExecution: true,
                    queue: queue
                )
            }
        }

        return AuthFileReadResult(url: linkedLocationValue.authFileURL, contents: currentContents)
    }

    func writeAuthFile(_ contents: String) async throws {
        guard linkedLocationValue != nil else {
            throw AuthFileAccessError.accessRequired
        }

        currentContents = contents
    }

    func startMonitoring(_ onChange: @escaping @Sendable () -> Void) async {
        self.onChange = onChange
    }

    func enableQueuedCommandOnNextRead() {
        currentContents = initialContents
        hasQueuedAdditionalCommand = false
        shouldQueueAdditionalCommandOnNextRead = true
    }
}
