//
//  CodexSharedProcessLock.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-08.
//

import Foundation

#if canImport(Darwin)
import Darwin
#endif

struct CodexSharedProcessLock: Sendable {
    private let baseURL: URL?

    nonisolated init(baseURL: URL? = nil) {
        self.baseURL = baseURL
    }

    nonisolated func withExclusiveAccess<T>(_ body: () throws -> T) throws -> T {
        let containerURL = try baseURL ?? CodexSharedAppGroup.containerURL()
        let lockURL = containerURL
            .appending(path: CodexSharedAppGroup.lockFilename, directoryHint: .notDirectory)

        if !FileManager.default.fileExists(atPath: lockURL.path) {
            FileManager.default.createFile(atPath: lockURL.path, contents: nil)
        }

        let fileDescriptor = open(lockURL.path, O_RDWR)
        guard fileDescriptor >= 0 else {
            throw POSIXError(.EIO)
        }

        defer { close(fileDescriptor) }

        guard flock(fileDescriptor, LOCK_EX) == 0 else {
            throw POSIXError(.EWOULDBLOCK)
        }

        defer { flock(fileDescriptor, LOCK_UN) }
        return try body()
    }
}
