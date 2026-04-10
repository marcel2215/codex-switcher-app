//
//  CodexSharedStores.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-08.
//

import Foundation

struct CodexSharedStateStore: Sendable {
    private let baseURL: URL?

    nonisolated init(baseURL: URL? = nil) {
        self.baseURL = baseURL
    }

    nonisolated func load() throws -> SharedCodexState {
        let fileURL = try stateFileURL()
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .empty
        }

        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(SharedCodexState.self, from: data)
    }

    nonisolated func save(_ state: SharedCodexState) throws {
        let fileURL = try stateFileURL()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: fileURL, options: [.atomic])
    }

    private nonisolated func stateFileURL() throws -> URL {
        let containerURL = try baseURL ?? CodexSharedAppGroup.containerURL()
        return containerURL.appending(path: CodexSharedAppGroup.stateFilename, directoryHint: .notDirectory)
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
