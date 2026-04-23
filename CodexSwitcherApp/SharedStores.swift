//
//  SharedStores.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-08.
//

import Foundation

struct CodexSharedStateStore: Sendable {
    private let baseURL: URL?
    private nonisolated static let ubiquitousStateKey = "SharedCodexState"

    nonisolated init(baseURL: URL? = nil) {
        self.baseURL = baseURL
    }

    nonisolated func load() throws -> SharedCodexState {
        // Widget extensions should still be able to recover from the mirrored
        // iCloud KVS snapshot even if the local App Group container is
        // temporarily unavailable or contains a stale/corrupt file.
        let appGroupState = try? loadAppGroupState()
        let ubiquitousState = loadUbiquitousState()

        switch (appGroupState, ubiquitousState) {
        case let (.some(appGroupState), .some(ubiquitousState)):
            return preferredState(primary: appGroupState, fallback: ubiquitousState)
        case let (.some(appGroupState), .none):
            return appGroupState
        case let (.none, .some(ubiquitousState)):
            return ubiquitousState
        case (.none, .none):
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

#if os(iOS) || os(watchOS) || os(tvOS)
        // Widgets and complications may need to read the shared snapshot while
        // the app itself is not running. Keep the file readable after the first
        // post-boot unlock instead of inheriting stricter protection classes.
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: fileURL.path
        )
#endif

        let ubiquitousStore = NSUbiquitousKeyValueStore.default
        ubiquitousStore.set(data, forKey: Self.ubiquitousStateKey)
        ubiquitousStore.synchronize()
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
        return try JSONDecoder().decode(SharedCodexState.self, from: data)
    }

    private nonisolated func loadUbiquitousState() -> SharedCodexState? {
        let ubiquitousStore = NSUbiquitousKeyValueStore.default
        ubiquitousStore.synchronize()
        guard let data = ubiquitousStore.data(forKey: Self.ubiquitousStateKey) else {
            return nil
        }

        return try? JSONDecoder().decode(SharedCodexState.self, from: data)
    }

    private nonisolated func preferredState(
        primary: SharedCodexState,
        fallback: SharedCodexState
    ) -> SharedCodexState {
        if fallback.updatedAt > primary.updatedAt {
            return fallback
        }

        if primary.accounts.isEmpty, !fallback.accounts.isEmpty {
            return fallback
        }

        return primary
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
        try data.write(to: fileURL, options: [.atomic])
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
