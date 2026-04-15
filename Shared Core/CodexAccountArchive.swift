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
    static let legacyCodexAccountArchive = UTType(
        importedAs: "com.marcel2215.codexswitcher.account-archive"
    )
    static let codexAccountArchive = UTType(
        exportedAs: "com.marcel2215.codexswitcher.account-archive-binary",
        conformingTo: .data
    )

    static let openableCodexAccountArchiveTypes: [UTType] = [
        .codexAccountArchive,
        .legacyCodexAccountArchive
    ]

    var isCodexAccountArchiveType: Bool {
        identifier == UTType.codexAccountArchive.identifier
            || identifier == UTType.legacyCodexAccountArchive.identifier
    }
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
    static let archiveFilenameExtension = UTType.codexAccountArchive.preferredFilenameExtension ?? "cxa"
    static let encodedArchiveHeader = Data([0x43, 0x58, 0x41, 0x01]) // "CXA" + container version 1
    // LZFSE is Foundation's usual Apple-platform default, but for these small
    // archives it can preserve readable plist literals in the output. Use zlib
    // so Finder and Quick Look see opaque bytes instead of previewable text.
    static let archiveCompressionAlgorithm: NSData.CompressionAlgorithm = .zlib

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

    static func exportFilename(for rawValue: String) -> String {
        "\(normalizedExportFilenameStem(from: rawValue)).\(archiveFilenameExtension)"
    }

    static func finalizedExportURL(from proposedURL: URL) -> URL {
        proposedURL
            .deletingLastPathComponent()
            .appendingPathComponent(exportFilename(for: proposedURL.lastPathComponent), isDirectory: false)
    }

    func encodedData() throws -> Data {
        try validate()

        // Wrap the archive plist in a versioned compressed envelope. Binary
        // plists still expose readable strings in Quick Look previews; the
        // compressed container keeps `.cxa` opaque while still relying on
        // Foundation's built-in compression and plist decoders.
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let propertyListData = try encoder.encode(self)
        let compressedPropertyListData = try Self.compressedArchivePayload(from: propertyListData)

        var encodedArchiveData = Self.encodedArchiveHeader
        encodedArchiveData.append(compressedPropertyListData)
        return encodedArchiveData
    }

    static func decode(from data: Data) throws -> CodexAccountArchive {
        if let decompressedPropertyListData = try decompressedArchivePayloadIfPresent(in: data) {
            let archive = try decodePropertyListArchive(from: decompressedPropertyListData)
            try archive.validate()
            return archive
        }

        do {
            let archive = try decodePropertyListArchive(from: data)
            try archive.validate()
            return archive
        } catch let error as CodexAccountArchiveError where error == .invalidData {
            return try decodeLegacyJSONArchive(from: data)
        } catch let error as CodexAccountArchiveError {
            throw error
        } catch {
            return try decodeLegacyJSONArchive(from: data)
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

    private static func compressedArchivePayload(from propertyListData: Data) throws -> Data {
        try (propertyListData as NSData).compressed(using: archiveCompressionAlgorithm) as Data
    }

    private static func decompressedArchivePayloadIfPresent(in data: Data) throws -> Data? {
        guard data.starts(with: encodedArchiveHeader) else {
            return nil
        }

        let compressedPayload = data.dropFirst(encodedArchiveHeader.count)
        guard !compressedPayload.isEmpty else {
            throw CodexAccountArchiveError.invalidData
        }

        do {
            return try (Data(compressedPayload) as NSData).decompressed(using: archiveCompressionAlgorithm) as Data
        } catch {
            throw CodexAccountArchiveError.invalidData
        }
    }

    private static func decodePropertyListArchive(from data: Data) throws -> CodexAccountArchive {
        do {
            return try PropertyListDecoder().decode(CodexAccountArchive.self, from: data)
        } catch let error as CodexAccountArchiveError {
            throw error
        } catch {
            throw CodexAccountArchiveError.invalidData
        }
    }

    private static func decodeLegacyJSONArchive(from data: Data) throws -> CodexAccountArchive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)

            // Older archives used Foundation's plain ISO 8601 strategy, which
            // drops fractional seconds. Keep accepting both forms so imports
            // stay backward compatible with the original JSON-based exports.
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
            CodexAccountArchive.exportFilename(for: request.resolvedSuggestedFilename),
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

    var exportedArchiveFilename: String {
        CodexAccountArchive.exportFilename(for: defaultFilename)
    }

    var availabilityKey: String {
        "\(request.identityKey)|\(request.hasLocalSnapshot)"
    }

    func canExport() async -> Bool {
        await exporter.canExport(request)
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .codexAccountArchive) { item in
            // Export a transferred file copy rather than exposing the original
            // temp URL in-place. Finder accepts that path more reliably for
            // drag-to-Desktop from a sandboxed app, while `suggestedFileName`
            // preserves the visible account-based filename.
            SentTransferredFile(try await item.exporter.exportFile(for: item.request))
        }
        .suggestedFileName { $0.exportedArchiveFilename }

        ProxyRepresentation(exporting: \.reorderToken)
    }
}

#if os(macOS)
extension CodexAccountArchiveTransferItem {
    func macOSItemProvider(includeReorderToken: Bool) -> NSItemProvider {
        let provider = NSItemProvider()
        // Finder treats `suggestedName` as the display name stem for promised
        // file drops and can append the registered content-type extension on
        // top. Keep the extension out of this field so Desktop drops do not
        // become `Account.cxa.cxa`.
        provider.suggestedName = defaultFilename

        let request = self.request
        let exporter = self.exporter
        provider.registerFileRepresentation(
            forTypeIdentifier: UTType.codexAccountArchive.identifier,
            fileOptions: [],
            visibility: .all
        ) { completion in
            Task {
                do {
                    let fileURL = try await exporter.exportFile(for: request)
                    completion(fileURL, false, nil)
                } catch {
                    completion(nil, false, error)
                }
            }

            return nil
        }

        // Keep the reorder token visible only inside the app process so Finder
        // sees a file drag, while the in-app drop destination can still reorder
        // rows using the same drag gesture.
        if includeReorderToken {
            provider.registerDataRepresentation(
                forTypeIdentifier: UTType.plainText.identifier,
                visibility: .ownProcess
            ) { completion in
                completion(Data(self.reorderToken.utf8), nil)
                return nil
            }
        }

        return provider
    }
}
#endif

extension CodexAccountArchive {
    nonisolated static func normalizedExportFilenameStem(from rawValue: String) -> String {
        let normalizedValue = normalizedOptionalString(rawValue) ?? fallbackSuggestedFilename
        let archiveExtension = ".\(archiveFilenameExtension)"
        var filenameStem = normalizedValue

        // People sometimes rename accounts to include the archive suffix. Strip
        // exactly that suffix before sanitizing so drag/share/export paths do
        // not end up producing duplicate `.cxa` extensions or an empty wrapper
        // name like `.cxa`.
        while filenameStem.lowercased().hasSuffix(archiveExtension.lowercased()) {
            filenameStem = String(filenameStem.dropLast(archiveExtension.count))
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
