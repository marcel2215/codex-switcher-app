//
//  CodexSwitcherTests.swift
//  Codex SwitcherTests
//
//  Created by Marcel Kwiatkowski on 2026-04-06.
//

import Foundation
import SwiftUI
import SwiftData
import Testing
@testable import Codex_Switcher

@MainActor
struct CodexSwitcherTests {
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

    @Test func capturePreventsDuplicatesAndKeepsSelectionOnExistingAccount() throws {
        let container = try makeInMemoryContainer()
        let fakeFileManager = FakeAuthFileManager(contents: makeChatGPTAuthJSON(accountID: "acct-123"))
        let controller = AppController(
            authFileManager: fakeFileManager,
            notificationManager: FakeNotificationManager()
        )

        controller.configure(modelContext: container.mainContext, undoManager: nil)
        controller.captureCurrentAccount()
        controller.captureCurrentAccount()

        let accounts = try fetchAccounts(in: container.mainContext)
        #expect(accounts.count == 1)
        #expect(controller.selection == [accounts[0].id])
        #expect(accounts[0].name == "Unnamed Account 1")
        #expect(accounts[0].iconSystemName == AccountIconOption.defaultOption.systemName)
    }

    @Test func captureAddsDistinctAccountsWhenStableSubjectDiffers() throws {
        let container = try makeInMemoryContainer()
        let fakeFileManager = FakeAuthFileManager(
            contents: makeChatGPTAuthJSON(
                accountID: "shared-account-id",
                userID: "user-one",
                subject: "auth0|user-one",
                email: "one@example.com"
            )
        )
        let controller = AppController(
            authFileManager: fakeFileManager,
            notificationManager: FakeNotificationManager()
        )

        controller.configure(modelContext: container.mainContext, undoManager: nil)
        controller.captureCurrentAccount()

        fakeFileManager.contents = makeChatGPTAuthJSON(
            accountID: "shared-account-id",
            userID: "user-two",
            subject: "auth0|user-two",
            email: "two@example.com"
        )
        controller.captureCurrentAccount()

        let accounts = try fetchAccounts(in: container.mainContext)
        #expect(accounts.count == 2)
        #expect(Set(accounts.map(\.emailHint)) == ["one@example.com", "two@example.com"])
    }

    @Test func switchingAccountWritesStoredSnapshotAndRefreshesLastLogin() async throws {
        let container = try makeInMemoryContainer()
        let fakeFileManager = FakeAuthFileManager(contents: makeChatGPTAuthJSON(accountID: "acct-original"))
        let controller = AppController(
            authFileManager: fakeFileManager,
            notificationManager: FakeNotificationManager()
        )

        controller.configure(modelContext: container.mainContext, undoManager: nil)

        let targetContents = makeChatGPTAuthJSON(accountID: "acct-target")
        let targetSnapshot = try CodexAuthFile.parse(contents: targetContents)
        let account = StoredAccount(
            identityKey: targetSnapshot.identityKey,
            name: "Unnamed Account 1",
            customOrder: 0,
            authFileContents: targetContents,
            authModeRaw: targetSnapshot.authMode.rawValue,
            emailHint: targetSnapshot.email,
            accountIdentifier: targetSnapshot.accountIdentifier
        )
        container.mainContext.insert(account)
        try container.mainContext.save()

        controller.login(accountID: account.id)
        try await Task.sleep(for: .milliseconds(100))

        let refreshedAccount = try #require(fetchAccounts(in: container.mainContext).first)
        #expect(fakeFileManager.contents == targetContents)
        #expect(refreshedAccount.lastLoginAt != nil)
        #expect(controller.selection == [account.id])
    }

    @Test func switchingAccountRecreatesAuthFileWhenCodexIsLoggedOut() async throws {
        let container = try makeInMemoryContainer()
        let fakeFileManager = FakeAuthFileManager(missingAuthFileURL: URL(fileURLWithPath: "/tmp/auth.json"))
        let controller = AppController(
            authFileManager: fakeFileManager,
            notificationManager: FakeNotificationManager()
        )

        controller.configure(modelContext: container.mainContext, undoManager: nil)

        let targetContents = makeChatGPTAuthJSON(accountID: "acct-target")
        let targetSnapshot = try CodexAuthFile.parse(contents: targetContents)
        let account = StoredAccount(
            identityKey: targetSnapshot.identityKey,
            name: "Unnamed Account 1",
            customOrder: 0,
            authFileContents: targetContents,
            authModeRaw: targetSnapshot.authMode.rawValue,
            emailHint: targetSnapshot.email,
            accountIdentifier: targetSnapshot.accountIdentifier
        )
        container.mainContext.insert(account)
        try container.mainContext.save()

        controller.login(accountID: account.id)
        try await Task.sleep(for: .milliseconds(100))

        let refreshedAccount = try #require(fetchAccounts(in: container.mainContext).first)
        #expect(fakeFileManager.contents == targetContents)
        #expect(refreshedAccount.lastLoginAt != nil)
        #expect(controller.selection == [account.id])
    }

    @Test func captureDoesNotShowAlertWhenFolderSelectionIsCancelled() throws {
        let container = try makeInMemoryContainer()
        let fakeFileManager = FakeAuthFileManager(
            contents: makeChatGPTAuthJSON(accountID: "acct-123"),
            readError: AuthFileAccessError.cancelled
        )
        let controller = AppController(
            authFileManager: fakeFileManager,
            notificationManager: FakeNotificationManager()
        )

        controller.configure(modelContext: container.mainContext, undoManager: nil)
        controller.captureCurrentAccount()

        #expect(controller.presentedAlert == nil)
        #expect(try fetchAccounts(in: container.mainContext).isEmpty)
    }

    @Test func loginDoesNotShowAlertWhenFolderSelectionIsCancelled() async throws {
        let container = try makeInMemoryContainer()
        let fakeFileManager = FakeAuthFileManager(
            contents: makeChatGPTAuthJSON(accountID: "acct-original"),
            writeError: AuthFileAccessError.cancelled
        )
        let controller = AppController(
            authFileManager: fakeFileManager,
            notificationManager: FakeNotificationManager()
        )

        controller.configure(modelContext: container.mainContext, undoManager: nil)

        let targetContents = makeChatGPTAuthJSON(accountID: "acct-target")
        let targetSnapshot = try CodexAuthFile.parse(contents: targetContents)
        let account = StoredAccount(
            identityKey: targetSnapshot.identityKey,
            name: "Unnamed Account 1",
            customOrder: 0,
            authFileContents: targetContents,
            authModeRaw: targetSnapshot.authMode.rawValue,
            emailHint: targetSnapshot.email,
            accountIdentifier: targetSnapshot.accountIdentifier
        )
        container.mainContext.insert(account)
        try container.mainContext.save()

        controller.login(accountID: account.id)
        try await Task.sleep(for: .milliseconds(100))

        let refreshedAccount = try #require(fetchAccounts(in: container.mainContext).first)
        #expect(controller.presentedAlert == nil)
        #expect(refreshedAccount.lastLoginAt == nil)
    }

    @Test func selectedAccountIconCanBeChanged() throws {
        let container = try makeInMemoryContainer()
        let fakeFileManager = FakeAuthFileManager(contents: makeChatGPTAuthJSON(accountID: "acct-123"))
        let controller = AppController(
            authFileManager: fakeFileManager,
            notificationManager: FakeNotificationManager()
        )

        controller.configure(modelContext: container.mainContext, undoManager: nil)
        controller.captureCurrentAccount()

        let account = try #require(fetchAccounts(in: container.mainContext).first)
        #expect(account.iconSystemName == AccountIconOption.defaultOption.systemName)

        controller.setIcon(.terminal, for: account.id)

        let updatedAccount = try #require(fetchAccounts(in: container.mainContext).first)
        #expect(updatedAccount.iconSystemName == AccountIconOption.terminal.systemName)
    }

    @Test func dragReorderMovesAccountToEndWithoutInvalidInsertIndex() async throws {
        let container = try makeInMemoryContainer()
        let controller = AppController(
            authFileManager: FakeAuthFileManager(contents: makeChatGPTAuthJSON(accountID: "acct-123")),
            notificationManager: FakeNotificationManager()
        )

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

        try await Task.sleep(for: .milliseconds(50))

        let reordered = controller.displayedAccounts(from: try fetchAccounts(in: container.mainContext))
        #expect(reordered.map(\.name) == ["Second", "Third", "First"])
        #expect(controller.presentedAlert == nil)
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
}

private func makeInMemoryContainer() throws -> ModelContainer {
    let schema = Schema([StoredAccount.self])
    let configuration = ModelConfiguration(
        "TestAccounts",
        schema: schema,
        isStoredInMemoryOnly: true,
        cloudKitDatabase: .none
    )
    return try ModelContainer(for: schema, configurations: [configuration])
}

private func fetchAccounts(in modelContext: ModelContext) throws -> [StoredAccount] {
    try modelContext.fetch(FetchDescriptor<StoredAccount>())
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
        authFileContents: contents,
        authModeRaw: snapshot.authMode.rawValue,
        emailHint: snapshot.email,
        accountIdentifier: snapshot.accountIdentifier
    )
}

private func makeJWT(_ payload: [String: Any]) -> String {
    let header = ["alg": "none", "typ": "JWT"]
    let headerData = try! JSONSerialization.data(withJSONObject: header)
    let payloadData = try! JSONSerialization.data(withJSONObject: payload)

    func encode(_ data: Data) -> String {
        data
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    return "\(encode(headerData)).\(encode(payloadData)).c2ln"
}

@MainActor
private final class FakeAuthFileManager: AuthFileManaging {
    var contents: String
    private let authFileURL: URL
    private var isMissing = false
    private let readError: Error?
    private let writeError: Error?

    init(
        contents: String,
        authFileURL: URL = URL(fileURLWithPath: "/tmp/auth.json"),
        readError: Error? = nil,
        writeError: Error? = nil
    ) {
        self.contents = contents
        self.authFileURL = authFileURL
        self.readError = readError
        self.writeError = writeError
    }

    init(missingAuthFileURL: URL) {
        self.contents = ""
        self.authFileURL = missingAuthFileURL
        self.isMissing = true
        self.readError = nil
        self.writeError = nil
    }

    func readAuthFile(promptIfNeeded: Bool) throws -> AuthFileReadResult {
        if let readError {
            throw readError
        }

        if isMissing {
            throw AuthFileAccessError.missingAuthFile(authFileURL)
        }

        return AuthFileReadResult(
            url: authFileURL,
            contents: contents
        )
    }

    func writeAuthFile(_ contents: String, promptIfNeeded: Bool) throws {
        if let writeError {
            throw writeError
        }

        self.contents = contents
        isMissing = false
    }
}

@MainActor
private final class FakeNotificationManager: AccountSwitchNotifying {
    func postSwitchNotification(for accountName: String) async {}
}
