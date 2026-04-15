//
//  CodexAccountArchive.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-14.
//

import CoreTransferable
import Foundation
import UniformTypeIdentifiers

nonisolated extension UTType {
    static let codexAccountArchive = UTType(
        exportedAs: "com.marcel2215.codexswitcher.account-archive",
        conformingTo: .json
    )
}

nonisolated enum CodexAccountArchiveError: LocalizedError, Equatable {
    case invalidData
    case unsupportedVersion(Int)
    case missingSnapshotContents

    var errorDescription: String? {
        switch self {
        case .invalidData:
            "That .cxa file isn't a valid Codex account archive."
        case .unsupportedVersion(let version):
            "This .cxa file uses unsupported archive version \(version)."
        case .missingSnapshotContents:
            "That .cxa file doesn't contain an account snapshot."
        }
    }
}

/// A portable account export that preserves the auth snapshot plus the
/// user-visible metadata needed to recreate a recognizable account entry.
nonisolated struct CodexAccountArchive: Codable, Sendable, Equatable {
    static let currentVersion = 1
    static let fallbackSuggestedFilename = "Codex Account"

    let version: Int
    let exportedAt: Date
    let name: String?
    let iconSystemName: String?
    let identityKey: String?
    let authModeRaw: String?
    let emailHint: String?
    let accountIdentifier: String?
    let snapshotContents: String

    init(
        version: Int = 1,
        exportedAt: Date = Date(),
        name: String?,
        iconSystemName: String?,
        identityKey: String?,
        authModeRaw: String?,
        emailHint: String?,
        accountIdentifier: String?,
        snapshotContents: String
    ) {
        self.version = version
        self.exportedAt = exportedAt
        self.name = Self.normalizedOptionalString(name)
        self.iconSystemName = Self.normalizedOptionalString(iconSystemName)
        self.identityKey = Self.normalizedOptionalString(identityKey)
        self.authModeRaw = Self.normalizedOptionalString(authModeRaw)
        self.emailHint = Self.normalizedOptionalString(emailHint)
        self.accountIdentifier = Self.normalizedOptionalString(accountIdentifier)
        self.snapshotContents = snapshotContents
    }

    var preferredStoredName: String? {
        Self.normalizedOptionalString(name)
    }

    var resolvedIconSystemName: String {
        Self.normalizedOptionalString(iconSystemName) ?? "key.fill"
    }

    var suggestedFilename: String {
        let preferredBaseName = preferredStoredName
            ?? Self.normalizedOptionalString(emailHint)
            ?? Self.normalizedOptionalString(accountIdentifier)
            ?? Self.fallbackSuggestedFilename
        return Self.sanitizedFilenameComponent(preferredBaseName)
    }

    func encodedData() throws -> Data {
        try validate()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Self.encodeArchiveDate(date))
        }
        return try encoder.encode(self)
    }

    static func decode(from data: Data) throws -> CodexAccountArchive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)

            // Older archives used Foundation's plain ISO 8601 strategy, which
            // drops fractional seconds. Keep accepting both forms so imports
            // stay backward compatible while new exports preserve precision.
            if let date = decodeArchiveDate(rawValue) {
                return date
            }

            throw CodexAccountArchiveError.invalidData
        }

        do {
            let archive = try decoder.decode(CodexAccountArchive.self, from: data)
            try archive.validate()
            return archive
        } catch let error as CodexAccountArchiveError {
            throw error
        } catch {
            throw CodexAccountArchiveError.invalidData
        }
    }

    private func validate() throws {
        guard version == Self.currentVersion else {
            throw CodexAccountArchiveError.unsupportedVersion(version)
        }

        guard !snapshotContents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CodexAccountArchiveError.missingSnapshotContents
        }
    }

    private static func normalizedOptionalString(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        return value
    }

    private static func encodeArchiveDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func decodeArchiveDate(_ rawValue: String) -> Date? {
        let formatterWithFractionalSeconds = ISO8601DateFormatter()
        formatterWithFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatterWithFractionalSeconds.date(from: rawValue) {
            return date
        }

        let formatterWithoutFractionalSeconds = ISO8601DateFormatter()
        formatterWithoutFractionalSeconds.formatOptions = [.withInternetDateTime]
        return formatterWithoutFractionalSeconds.date(from: rawValue)
    }

    private static func sanitizedFilenameComponent(_ rawValue: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>").union(.controlCharacters)
        let cleanedScalars = rawValue.unicodeScalars.map { scalar in
            invalidCharacters.contains(scalar) ? "-" : Character(scalar)
        }
        let cleaned = String(cleanedScalars)
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.whitespacesAndNewlines))

        return cleaned.isEmpty ? "Codex Account" : cleaned
    }
}

nonisolated struct CodexAccountArchiveExportRequest: Sendable, Equatable {
    let name: String?
    let iconSystemName: String
    let identityKey: String
    let hasLocalSnapshot: Bool
    let authModeRaw: String
    let emailHint: String?
    let accountIdentifier: String?
    let suggestedFilename: String

    var resolvedSuggestedFilename: String {
        CodexAccountArchive.normalizedExportFilenameStem(from: suggestedFilename)
    }

    @MainActor
    init(account: StoredAccount) {
        self.name = account.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : account.name
        self.iconSystemName = account.iconSystemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "key.fill"
            : account.iconSystemName
        self.identityKey = account.identityKey
        self.hasLocalSnapshot = account.hasLocalSnapshot
        self.authModeRaw = account.authModeRaw
        self.emailHint = account.emailHint
        self.accountIdentifier = account.accountIdentifier
        self.suggestedFilename = CodexAccountArchive(
            name: self.name ?? AccountsPresentationLogic.displayName(for: account),
            iconSystemName: self.iconSystemName,
            identityKey: self.identityKey,
            authModeRaw: self.authModeRaw,
            emailHint: self.emailHint,
            accountIdentifier: self.accountIdentifier,
            snapshotContents: "{}"
        ).suggestedFilename
    }
}

actor CodexAccountArchiveFileExporter {
    private let snapshotStore: AccountSnapshotStoring
    private let fileManager: FileManager
    private let exportDirectoryURL: URL

    init(
        snapshotStore: AccountSnapshotStoring = SharedKeychainSnapshotStore(),
        fileManager: FileManager = .default
    ) {
        self.snapshotStore = snapshotStore
        self.fileManager = fileManager
        self.exportDirectoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("CodexAccountArchiveExports", isDirectory: true)
    }

    func canExport(_ request: CodexAccountArchiveExportRequest) async -> Bool {
        await snapshotStore.containsSnapshot(forIdentityKey: request.identityKey)
    }

    func exportData(for request: CodexAccountArchiveExportRequest) async throws -> Data {
        let snapshotContents = try await snapshotStore.loadSnapshot(forIdentityKey: request.identityKey)
        let archive = CodexAccountArchive(
            name: request.name,
            iconSystemName: request.iconSystemName,
            identityKey: request.identityKey,
            authModeRaw: request.authModeRaw,
            emailHint: request.emailHint,
            accountIdentifier: request.accountIdentifier,
            snapshotContents: snapshotContents
        )
        return try archive.encodedData()
    }

    func exportFile(for request: CodexAccountArchiveExportRequest) async throws -> URL {
        let archiveData = try await exportData(for: request)

        try fileManager.createDirectory(
            at: exportDirectoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        let exportInstanceDirectoryURL = exportDirectoryURL.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: exportInstanceDirectoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        // Keep the visible filename stable for Finder, Files, and share-sheet
        // targets while isolating each export in its own temp directory so
        // repeated drags or shares do not collide with one another.
        let fileURL = exportInstanceDirectoryURL.appendingPathComponent(
            "\(request.resolvedSuggestedFilename).cxa",
            isDirectory: false
        )
        try archiveData.write(to: fileURL, options: .atomic)
        return fileURL
    }
}

/// Exposes a `.cxa` archive as a modern Transferable so the same item can back
/// drag-and-drop, `ShareLink`, and SwiftUI's latest `fileExporter(item:)` API.
nonisolated struct CodexAccountArchiveTransferItem: Transferable, Sendable {
    let request: CodexAccountArchiveExportRequest
    let reorderToken: String

    fileprivate let exporter: CodexAccountArchiveFileExporter

    init(
        request: CodexAccountArchiveExportRequest,
        reorderToken: String = "",
        exporter: CodexAccountArchiveFileExporter
    ) {
        self.request = request
        self.reorderToken = reorderToken
        self.exporter = exporter
    }

    var defaultFilename: String {
        request.resolvedSuggestedFilename
    }

    var availabilityKey: String {
        "\(request.identityKey)|\(request.hasLocalSnapshot)"
    }

    func canExport() async -> Bool {
        await exporter.canExport(request)
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(
            exportedContentType: .codexAccountArchive,
            shouldAllowToOpenInPlace: true
        ) { item in
            // Finder/Desktop derive the dragged filename from the handed-off
            // file URL on disk. Allowing open-in-place keeps the visible drop
            // name aligned with the account-derived `.cxa` filename rather
            // than a transient NSItemProvider temp filename.
            SentTransferredFile(
                try await item.exporter.exportFile(for: item.request),
                allowAccessingOriginalFile: true
            )
        }

        ProxyRepresentation(exporting: \.reorderToken)
    }
}

private extension CodexAccountArchive {
    nonisolated static func normalizedExportFilenameStem(from rawValue: String) -> String {
        let normalizedValue = normalizedOptionalString(rawValue) ?? fallbackSuggestedFilename
        let archiveExtension = ".\(UTType.codexAccountArchive.preferredFilenameExtension ?? "cxa")"
        let filenameStem: String

        // People sometimes rename accounts to include the archive suffix. Strip
        // exactly that suffix before sanitizing so drag/share/export paths do
        // not end up producing duplicate `.cxa` extensions or an empty wrapper
        // name like `.cxa`.
        if normalizedValue.lowercased().hasSuffix(archiveExtension.lowercased()) {
            filenameStem = String(normalizedValue.dropLast(archiveExtension.count))
        } else {
            filenameStem = normalizedValue
        }

        let sanitizedStem = sanitizedFilenameComponent(filenameStem)
        let bareArchiveExtension = String(archiveExtension.dropFirst())

        // If the visible name collapses to just the archive extension token,
        // prefer the standard fallback instead of exporting `cxa.cxa`.
        if sanitizedStem.compare(bareArchiveExtension, options: [.caseInsensitive]) == .orderedSame {
            return fallbackSuggestedFilename
        }

        return sanitizedStem
    }
}
