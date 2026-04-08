//
//  CodexSwitcherTests.swift
//  Codex SwitcherTests
//
//  Created by Marcel Kwiatkowski on 2026-04-06.
//

import Foundation
import SwiftData
import SwiftUI
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

    @Test func capturePreventsDuplicatesAndKeepsSelectionOnExistingAccount() async throws {
        let container = try makeInMemoryContainer()
        let authFileManager = FakeAuthFileManager(contents: makeChatGPTAuthJSON(accountID: "acct-123"))
        let secretStore = FakeSecretStore()
        let controller = makeController(
            authFileManager: authFileManager,
            secretStore: secretStore
        )

        controller.configure(modelContext: container.mainContext, undoManager: nil)
        await controller.captureCurrentAccountNow()
        await controller.captureCurrentAccountNow()

        let accounts = try fetchAccounts(in: container.mainContext)
        let account = try #require(accounts.first)

        #expect(accounts.count == 1)
        #expect(controller.selection == [account.id])
        #expect(account.name == "Account 1")
        #expect(account.iconSystemName == AccountIconOption.defaultOption.systemName)
        #expect(account.authFileContents == makeChatGPTAuthJSON(accountID: "acct-123"))
        #expect(await secretStore.secret(for: account.id) == makeChatGPTAuthJSON(accountID: "acct-123"))
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
        let controller = makeController(
            authFileManager: FakeAuthFileManager(contents: makeChatGPTAuthJSON(accountID: "acct-current")),
            secretStore: secretStore
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
        #expect(migratedAccount.authFileContents == legacyContents)
        #expect(await secretStore.secret(for: migratedAccount.id) == legacyContents)
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
        #expect(try fetchAccounts(in: container.mainContext).first?.authFileContents == targetContents)
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

        #expect(AccountRowView.makeLastLoginDescription(from: nil, relativeTo: now) == "Last login: never")
        #expect(AccountRowView.makeLastLoginDescription(from: now.addingTimeInterval(-(59 * 60)), relativeTo: now) == "Last login: this hour")
        #expect(AccountRowView.makeLastLoginDescription(from: now.addingTimeInterval(-(1 * 60 * 60)), relativeTo: now) == "Last login: 1 hour ago")
        #expect(AccountRowView.makeLastLoginDescription(from: now.addingTimeInterval(-(10 * 60 * 60)), relativeTo: now) == "Last login: 10 hours ago")
        #expect(AccountRowView.makeLastLoginDescription(from: now.addingTimeInterval(-(24 * 60 * 60)), relativeTo: now) == "Last login: 1 day ago")
        #expect(AccountRowView.makeLastLoginDescription(from: now.addingTimeInterval(-(7 * 24 * 60 * 60)), relativeTo: now) == "Last login: 7 days ago")
        #expect(AccountRowView.makeLastLoginDescription(from: now.addingTimeInterval(-(3_432 * 24 * 60 * 60)), relativeTo: now) == "Last login: 3432 days ago")
        #expect(AccountRowView.makeLastLoginDescription(from: now.addingTimeInterval(5 * 60), relativeTo: now) == "Last login: this hour")
    }

    @Test func iconCatalogOffersExpandedChoicesAndKeepsKeyDefault() {
        #expect(AccountIconOption.allCases.count >= 30)
        #expect(AccountIconOption.defaultOption == .key)
        #expect(AccountIconOption.resolve(from: "not-a-real-symbol") == .key)
    }

    @Test func startupReconcilesDuplicateAccountsForTheSameIdentityKey() async throws {
        let container = try makeInMemoryContainer()
        let controller = makeController(
            authFileManager: FakeAuthFileManager(contents: makeChatGPTAuthJSON(accountID: "acct-current"))
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
        #expect(reconciledAccount.authFileContents == duplicateContents)
    }
}

@MainActor
private func makeController(
    authFileManager: FakeAuthFileManager,
    secretStore: FakeSecretStore = FakeSecretStore(),
    notificationManager: FakeNotificationManager = FakeNotificationManager()
) -> AppController {
    AppController(
        authFileManager: authFileManager,
        secretStore: secretStore,
        notificationManager: notificationManager
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

actor FakeAuthFileManager: AuthFileManaging {
    private(set) var currentContents: String
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

    func linkedLocation() async -> AuthLinkedLocation? {
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

actor FakeSecretStore: AccountSecretStoring {
    private var secrets: [UUID: String] = [:]
    private var saveError: Error?
    private var loadError: Error?
    private var deleteError: Error?

    func saveSecret(_ contents: String, for accountID: UUID) async throws {
        if let saveError {
            throw saveError
        }

        secrets[accountID] = contents
    }

    func loadSecret(for accountID: UUID) async throws -> String {
        if let loadError {
            throw loadError
        }

        guard let secret = secrets[accountID] else {
            throw AccountSecretStoreError.missingSecret
        }

        return secret
    }

    func deleteSecret(for accountID: UUID) async throws {
        if let deleteError {
            throw deleteError
        }

        secrets.removeValue(forKey: accountID)
    }

    func secret(for accountID: UUID) async -> String? {
        secrets[accountID]
    }
}

@MainActor
final class FakeNotificationManager: AccountSwitchNotifying {
    private(set) var postedAccountNames: [String] = []

    func postSwitchNotification(for accountName: String) async {
        postedAccountNames.append(accountName)
    }
}
