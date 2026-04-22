//
//  CodexAccountArchiveTests.swift
//  Codex Switcher Tests
//
//  Created by Codex on 2026-04-14.
//

import Foundation
import Testing
import UniformTypeIdentifiers
@testable import CodexSwitcher

struct CodexAccountArchiveTests {
    @Test func archiveRoundTripPreservesMetadata() throws {
        let exportedAt = Date(timeIntervalSince1970: 1_700_000_000.123)
        let archive = CodexAccountArchive(
            exportedAt: exportedAt,
            name: "Work Account",
            iconSystemName: "briefcase.fill",
            identityKey: "chatgpt:abc123",
            authModeRaw: CodexAuthMode.chatgpt.rawValue,
            emailHint: "work@example.com",
            accountIdentifier: "workspace-123",
            snapshotContents: #"{"tokens":{"access_token":"abc"}}"#
        )

        let decodedArchive = try CodexAccountArchive.decode(from: archive.encodedData())

        #expect(decodedArchive == archive)
        #expect(decodedArchive.exportedAt == exportedAt)
        #expect(decodedArchive.suggestedFilename == "Work Account")
    }

    @Test func multiAccountArchiveRoundTripPreservesEveryEntry() throws {
        let archive = CodexAccountArchive(
            accounts: [
                .init(
                    name: "Work Account",
                    iconSystemName: "briefcase.fill",
                    identityKey: "chatgpt:work",
                    authModeRaw: CodexAuthMode.chatgpt.rawValue,
                    emailHint: "work@example.com",
                    accountIdentifier: "workspace-1",
                    snapshotContents: #"{"tokens":{"access_token":"work"}}"#
                ),
                .init(
                    name: "Personal Account",
                    iconSystemName: "person.fill",
                    identityKey: "chatgpt:personal",
                    authModeRaw: CodexAuthMode.chatgpt.rawValue,
                    emailHint: "personal@example.com",
                    accountIdentifier: "workspace-2",
                    snapshotContents: #"{"tokens":{"access_token":"personal"}}"#
                )
            ]
        )

        let decodedArchive = try CodexAccountArchive.decode(from: archive.encodedData())

        #expect(decodedArchive.accounts == archive.accounts)
        #expect(decodedArchive.containsMultipleAccounts)
        #expect(decodedArchive.suggestedFilename == "2 Codex Accounts")
    }

    @Test func archiveEncodingUsesOpaqueCompressedContainerFormat() throws {
        let archive = CodexAccountArchive(
            name: "Binary Archive",
            iconSystemName: "archivebox.fill",
            identityKey: "chatgpt:abc123",
            authModeRaw: CodexAuthMode.chatgpt.rawValue,
            emailHint: "binary@example.com",
            accountIdentifier: "workspace-123",
            snapshotContents: #"{"tokens":{"access_token":"abc"}}"#
        )

        let encodedData = try archive.encodedData()

        #expect(encodedData.starts(with: CodexAccountArchive.encodedArchiveHeader))
        #expect(encodedData.starts(with: Data("bplist".utf8)) == false)
        #expect(encodedData.range(of: Data("Binary Archive".utf8)) == nil)
        #expect(encodedData.range(of: Data("access_token".utf8)) == nil)
    }

    @Test func archiveTypeStillBehavesLikeAFileDataType() {
        #expect(UTType.codexAccountArchive.conforms(to: .data))
        #expect(UTType.codexAccountArchive.identifier == "com.marcel2215.codexswitcher.account-archive-binary")
    }

    @Test func legacyArchiveTypeStillRecognizesOlderIdentifiers() {
        #expect(UTType.legacyCodexAccountArchive.identifier == "com.marcel2215.codexswitcher.account-archive")
        #expect(UTType.legacyCodexAccountArchive.isCodexAccountArchiveType)
        #expect(UTType.codexAccountArchive.isCodexAccountArchiveType)
    }

    @Test func decodeAcceptsLegacyBinaryPropertyListArchives() throws {
        let archive = CodexAccountArchive(
            name: "Legacy Binary Archive",
            iconSystemName: "archivebox.fill",
            identityKey: "chatgpt:abc123",
            authModeRaw: CodexAuthMode.chatgpt.rawValue,
            emailHint: "legacy@example.com",
            accountIdentifier: "workspace-123",
            snapshotContents: #"{"tokens":{"access_token":"abc"}}"#
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary

        let decodedArchive = try CodexAccountArchive.decode(from: try encoder.encode(archive))

        #expect(decodedArchive == archive)
    }

    @Test func decodeAcceptsLegacyJSONArchives() throws {
        let legacyArchiveData = """
        {
          "accountIdentifier" : "workspace-123",
          "authModeRaw" : "chatgpt",
          "emailHint" : "work@example.com",
          "exportedAt" : "2026-04-14T12:00:00Z",
          "iconSystemName" : "briefcase.fill",
          "identityKey" : "chatgpt:abc123",
          "name" : "Work Account",
          "snapshotContents" : "{\\"tokens\\":{\\"access_token\\":\\"abc\\"}}",
          "version" : 1
        }
        """.data(using: .utf8)!

        let decodedArchive = try CodexAccountArchive.decode(from: legacyArchiveData)

        #expect(decodedArchive.name == "Work Account")
        #expect(decodedArchive.identityKey == "chatgpt:abc123")
        #expect(decodedArchive.snapshotContents == #"{"tokens":{"access_token":"abc"}}"#)
    }

    @Test func suggestedFilenameSanitizesUnsafeCharacters() {
        let archive = CodexAccountArchive(
            name: #"Work/Personal:Main?"#,
            iconSystemName: "person.fill",
            identityKey: nil,
            authModeRaw: CodexAuthMode.chatgpt.rawValue,
            emailHint: nil,
            accountIdentifier: nil,
            snapshotContents: #"{"tokens":{"access_token":"abc"}}"#
        )

        #expect(archive.suggestedFilename == "Work-Personal-Main-")
    }

    @MainActor
    @Test func exportRequestResolvedFilenameFallsBackAndStripsArchiveExtension() {
        let blankFilenameAccount = StoredAccount(
            identityKey: "chatgpt:abc123",
            name: ".cxa",
            createdAt: .now,
            customOrder: 0,
            hasLocalSnapshot: true,
            authModeRaw: CodexAuthMode.chatgpt.rawValue,
            emailHint: nil,
            accountIdentifier: nil,
            iconSystemName: "key.fill"
        )
        let duplicateExtensionAccount = StoredAccount(
            identityKey: "chatgpt:def456",
            name: "Work Account.CXA",
            createdAt: .now,
            customOrder: 1,
            hasLocalSnapshot: true,
            authModeRaw: CodexAuthMode.chatgpt.rawValue,
            emailHint: nil,
            accountIdentifier: nil,
            iconSystemName: "briefcase.fill"
        )
        let blankRequest = CodexAccountArchiveExportRequest(account: blankFilenameAccount)
        let duplicateExtensionRequest = CodexAccountArchiveExportRequest(account: duplicateExtensionAccount)

        #expect(blankRequest.resolvedSuggestedFilename == CodexAccountArchive.fallbackSuggestedFilename)
        #expect(duplicateExtensionRequest.resolvedSuggestedFilename == "Work Account")
    }

    @Test func exportFilenameAlwaysEndsWithASingleArchiveExtension() {
        #expect(CodexAccountArchive.exportFilename(for: "Work Account") == "Work Account.cxa")
        #expect(CodexAccountArchive.exportFilename(for: "Work Account.cxa") == "Work Account.cxa")
        #expect(CodexAccountArchive.exportFilename(for: "Work Account.cxa.cxa") == "Work Account.cxa")
        #expect(CodexAccountArchive.exportFilename(for: ".cxa.cxa") == "Codex Account.cxa")
    }

    @Test func finalizedExportURLCollapsesRepeatedArchiveExtensions() {
        let url = URL(fileURLWithPath: "/tmp/Work Account.cxa.cxa")

        #expect(CodexAccountArchive.finalizedExportURL(from: url).lastPathComponent == "Work Account.cxa")
    }

    @MainActor
    @Test func exportRequestPrefersExplicitAccountNameForFilename() {
        let account = StoredAccount(
            identityKey: "chatgpt:abc123",
            name: "Team Sandbox",
            createdAt: .now,
            customOrder: 0,
            hasLocalSnapshot: true,
            authModeRaw: CodexAuthMode.chatgpt.rawValue,
            emailHint: "work@example.com",
            accountIdentifier: "workspace-123",
            iconSystemName: "briefcase.fill"
        )

        let request = CodexAccountArchiveExportRequest(account: account)

        #expect(request.suggestedFilename == "Team Sandbox")
        #expect(request.resolvedSuggestedFilename == "Team Sandbox")
    }

    @MainActor
    @Test func batchExportRequestUsesPluralFilenameForMultipleAccounts() {
        let firstAccount = StoredAccount(
            identityKey: "chatgpt:first",
            name: "First",
            createdAt: .now,
            customOrder: 0,
            hasLocalSnapshot: true,
            authModeRaw: CodexAuthMode.chatgpt.rawValue,
            emailHint: nil,
            accountIdentifier: nil,
            iconSystemName: "briefcase.fill"
        )
        let secondAccount = StoredAccount(
            identityKey: "chatgpt:second",
            name: "Second",
            createdAt: .now,
            customOrder: 1,
            hasLocalSnapshot: true,
            authModeRaw: CodexAuthMode.chatgpt.rawValue,
            emailHint: nil,
            accountIdentifier: nil,
            iconSystemName: "person.fill"
        )

        let request = CodexAccountArchiveBatchExportRequest(
            accounts: [
                CodexAccountArchiveExportRequest(account: firstAccount),
                CodexAccountArchiveExportRequest(account: secondAccount)
            ]
        )

        #expect(request.resolvedSuggestedFilename == "2 Codex Accounts")
    }

    @MainActor
    @Test func transferItemUsesArchiveFilenameWithExtension() {
        let account = StoredAccount(
            identityKey: "chatgpt:abc123",
            name: "Team Sandbox",
            createdAt: .now,
            customOrder: 0,
            hasLocalSnapshot: true,
            authModeRaw: CodexAuthMode.chatgpt.rawValue,
            emailHint: "work@example.com",
            accountIdentifier: "workspace-123",
            iconSystemName: "briefcase.fill"
        )
        let transferItem = CodexAccountArchiveTransferItem(
            request: CodexAccountArchiveExportRequest(account: account),
            exporter: CodexAccountArchiveFileExporter(snapshotStore: FakeArchiveSnapshotStore())
        )

        #expect(transferItem.exportedArchiveFilename == "Team Sandbox.cxa")
    }

#if os(macOS)
    @MainActor
    @Test func macOSItemProviderUsesFilenameStemAsSuggestedName() {
        let account = StoredAccount(
            identityKey: "chatgpt:abc123",
            name: "Team Sandbox",
            createdAt: .now,
            customOrder: 0,
            hasLocalSnapshot: true,
            authModeRaw: CodexAuthMode.chatgpt.rawValue,
            emailHint: "work@example.com",
            accountIdentifier: "workspace-123",
            iconSystemName: "briefcase.fill"
        )
        let transferItem = CodexAccountArchiveTransferItem(
            request: CodexAccountArchiveExportRequest(account: account),
            exporter: CodexAccountArchiveFileExporter(snapshotStore: FakeArchiveSnapshotStore())
        )

        #expect(transferItem.macOSItemProvider(includeReorderToken: true).suggestedName == "Team Sandbox")
    }
#endif

    @Test func decodeRejectsMissingSnapshotContents() {
        let invalidArchiveData = """
        {
          "accountIdentifier" : "workspace-123",
          "authModeRaw" : "chatgpt",
          "emailHint" : "work@example.com",
          "exportedAt" : "2026-04-14T12:00:00Z",
          "iconSystemName" : "briefcase.fill",
          "identityKey" : "chatgpt:abc123",
          "name" : "Work Account",
          "snapshotContents" : "   ",
          "version" : 1
        }
        """.data(using: .utf8)!

        #expect(throws: CodexAccountArchiveError.self) {
            try CodexAccountArchive.decode(from: invalidArchiveData)
        }
    }

    @MainActor
    @Test func exporterPreservesStableFilenameForSharedFiles() async throws {
        let snapshotStore = FakeArchiveSnapshotStore()
        let identityKey = "chatgpt:abc123"
        try await snapshotStore.saveSnapshot(
            #"{"tokens":{"access_token":"abc"}}"#,
            forIdentityKey: identityKey
        )
        let account = StoredAccount(
            identityKey: identityKey,
            name: "Work Account",
            createdAt: .now,
            customOrder: 0,
            hasLocalSnapshot: true,
            authModeRaw: CodexAuthMode.chatgpt.rawValue,
            emailHint: "work@example.com",
            accountIdentifier: "workspace-123",
            iconSystemName: "briefcase.fill"
        )
        let request = CodexAccountArchiveExportRequest(account: account)

        let exporter = CodexAccountArchiveFileExporter(snapshotStore: snapshotStore)
        let fileURL = try await exporter.exportFile(for: request)
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        #expect(fileURL.lastPathComponent == "Work Account.cxa")
    }

    @MainActor
    @Test func exporterBundlesMultipleAccountsIntoOneArchiveFile() async throws {
        let snapshotStore = FakeArchiveSnapshotStore()
        try await snapshotStore.saveSnapshot(
            #"{"tokens":{"access_token":"first"}}"#,
            forIdentityKey: "chatgpt:first"
        )
        try await snapshotStore.saveSnapshot(
            #"{"tokens":{"access_token":"second"}}"#,
            forIdentityKey: "chatgpt:second"
        )

        let request = CodexAccountArchiveBatchExportRequest(
            accounts: [
                CodexAccountArchiveExportRequest(
                    account: StoredAccount(
                        identityKey: "chatgpt:first",
                        name: "First",
                        createdAt: .now,
                        customOrder: 0,
                        hasLocalSnapshot: true,
                        authModeRaw: CodexAuthMode.chatgpt.rawValue,
                        emailHint: "first@example.com",
                        accountIdentifier: "workspace-1",
                        iconSystemName: "briefcase.fill"
                    )
                ),
                CodexAccountArchiveExportRequest(
                    account: StoredAccount(
                        identityKey: "chatgpt:second",
                        name: "Second",
                        createdAt: .now,
                        customOrder: 1,
                        hasLocalSnapshot: true,
                        authModeRaw: CodexAuthMode.chatgpt.rawValue,
                        emailHint: "second@example.com",
                        accountIdentifier: "workspace-2",
                        iconSystemName: "person.fill"
                    )
                )
            ]
        )

        let exporter = CodexAccountArchiveFileExporter(snapshotStore: snapshotStore)
        let archive = try CodexAccountArchive.decode(from: try await exporter.exportData(for: request))

        #expect(archive.accounts.count == 2)
        #expect(archive.accounts.map(\.identityKey) == ["chatgpt:first", "chatgpt:second"])
    }
}

private final class FakeArchiveSnapshotStore: @unchecked Sendable, AccountSnapshotStoring {
    private let lock = NSLock()
    private var snapshots: [String: String] = [:]

    func saveSnapshot(_ contents: String, forIdentityKey identityKey: String) async throws {
        withLock {
            snapshots[identityKey] = contents
        }
    }

    func loadSnapshot(forIdentityKey identityKey: String) async throws -> String {
        try withLock {
            guard let snapshot = snapshots[identityKey] else {
                throw AccountSnapshotStoreError.missingSnapshot
            }

            return snapshot
        }
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
        false
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}
