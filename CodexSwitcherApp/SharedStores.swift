//
//  SharedStores.swift
//  Codex Switcher
//
//  Created by Marcel Kwiatkowski on 2026-04-08.
//

import Foundation
import OSLog

enum CodexSharedFileProtection {
    nonisolated static func apply(to url: URL) throws {
#if os(iOS) || os(watchOS) || os(tvOS)
        // Widgets, controls, complications, and background refresh may need
        // these shared files before the foreground app is running.
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
#else
        _ = url
#endif
    }
}

enum CodexCorruptSharedFileQuarantine {
    nonisolated static func moveAside(_ fileURL: URL, reason: String) throws -> URL {
        let timestamp = Int(Date().timeIntervalSince1970)
        let backupName = "\(fileURL.lastPathComponent).\(reason).corrupt-\(timestamp)"
        let backupURL = fileURL
            .deletingLastPathComponent()
            .appending(path: backupName, directoryHint: .notDirectory)

        try? FileManager.default.removeItem(at: backupURL)
        try FileManager.default.moveItem(at: fileURL, to: backupURL)
        return backupURL
    }
}

enum CodexSharedContainerPreflight {
    private nonisolated static let logger = Logger(
        subsystem: CodexSharedApplicationIdentity.mainApplicationBundleIdentifier,
        category: "SharedContainerPreflight"
    )

    nonisolated static func check() throws {
        let containerURL = try CodexSharedAppGroup.containerURL()
        try FileManager.default.createDirectory(
            at: containerURL,
            withIntermediateDirectories: true
        )

        guard UserDefaults(suiteName: CodexSharedAppGroup.identifier) != nil else {
            throw CodexSharedDataStoreError.containerUnavailable(CodexSharedAppGroup.identifier)
        }

        let accessGroup = CodexSharedKeychainAccessGroup.identifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accessGroup.isEmpty, !accessGroup.contains("$(") else {
            throw CodexSharedDataStoreError.keychainAccessGroupUnavailable
        }
    }

    nonisolated static func logFailureIfNeeded() {
        do {
            try check()
        } catch {
            logger.error("Shared container preflight failed: \(String(describing: error), privacy: .private)")
        }
    }
}

struct CodexSharedStateStore: Sendable {
    private let baseURL: URL?
    private let logger = Logger(
        subsystem: CodexSharedApplicationIdentity.mainApplicationBundleIdentifier,
        category: "SharedState"
    )

    nonisolated init(baseURL: URL? = nil) {
        self.baseURL = baseURL
    }

    nonisolated func load() throws -> SharedCodexState {
        try loadAppGroupState() ?? .empty
    }

    nonisolated func loadBestEffort() -> SharedCodexState {
        do {
            return try load()
        } catch {
            logger.error("Failed to load shared Codex state: \(String(describing: error), privacy: .private)")
            return .empty
        }
    }

    nonisolated func save(_ state: SharedCodexState) throws {
        let fileURL = try stateFileURL()
        let directoryURL = fileURL.deletingLastPathComponent()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(state)

        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        try data.write(to: fileURL, options: [.atomic])
        try CodexSharedFileProtection.apply(to: fileURL)
    }

    nonisolated func saveMergingRuntimeFields(_ incoming: SharedCodexState) throws {
        let lock = CodexSharedProcessLock(baseURL: baseURL)
        try lock.withExclusiveAccess {
            let existing = loadBestEffort()
            try save(mergeRuntimeFields(incoming: incoming, existing: existing))
        }
    }

    private nonisolated func stateFileURL() throws -> URL {
        let containerURL = try baseURL ?? CodexSharedAppGroup.containerURL()
        return containerURL.appending(path: CodexSharedAppGroup.stateFilename, directoryHint: .notDirectory)
    }

    private nonisolated func loadAppGroupState() throws -> SharedCodexState? {
        let fileURL = try stateFileURL()
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            return .empty
        }

        return try JSONDecoder().decode(SharedCodexState.self, from: data)
    }

    private nonisolated func mergeRuntimeFields(
        incoming: SharedCodexState,
        existing: SharedCodexState
    ) -> SharedCodexState {
        guard incoming.updatedAt < existing.updatedAt else {
            return incoming
        }

        var merged = incoming
        merged.authState = existing.authState
        merged.linkedFolderPath = existing.linkedFolderPath
        merged.currentAccountID = existing.currentAccountID

        var latestLastLoginByID: [String: Date] = [:]
        for account in existing.accounts {
            guard let lastLoginAt = account.lastLoginAt else {
                continue
            }

            if let current = latestLastLoginByID[account.id] {
                latestLastLoginByID[account.id] = max(current, lastLoginAt)
            } else {
                latestLastLoginByID[account.id] = lastLoginAt
            }
        }

        merged.accounts = merged.accounts.map { account in
            var copy = account
            if let existingLastLogin = latestLastLoginByID[account.id],
               (copy.lastLoginAt ?? .distantPast) < existingLastLogin {
                copy.lastLoginAt = existingLastLogin
            }
            return copy
        }

        return merged
    }
}

struct CodexSharedBookmarkStore: Sendable {
    private let baseURL: URL?
    private let filename: String

    nonisolated init(
        baseURL: URL? = nil,
        filename: String = CodexSharedAppGroup.bookmarkFilename
    ) {
        self.baseURL = baseURL
        self.filename = filename
    }

    nonisolated func load() throws -> Data? {
        let fileURL = try bookmarkFileURL()
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        return try Data(contentsOf: fileURL)
    }

    nonisolated func save(_ data: Data) throws {
        let fileURL = try bookmarkFileURL()
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: [.atomic])
        try CodexSharedFileProtection.apply(to: fileURL)
    }

    nonisolated func clear() throws {
        let fileURL = try bookmarkFileURL()
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }

        try FileManager.default.removeItem(at: fileURL)
    }

    private nonisolated func bookmarkFileURL() throws -> URL {
        let containerURL = try baseURL ?? CodexSharedAppGroup.containerURL()
        return containerURL.appending(path: filename, directoryHint: .notDirectory)
    }
}
