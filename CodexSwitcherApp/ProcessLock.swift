//
//  ProcessLock.swift
//  Codex Switcher
//
//  Created by Marcel Kwiatkowski on 2026-04-08.
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
        let fileDescriptor = try openLockFile()
        defer { close(fileDescriptor) }

        try acquireLock(fileDescriptor)
        defer { flock(fileDescriptor, LOCK_UN) }
        return try body()
    }

    nonisolated func withExclusiveAccess<T>(_ body: () async throws -> T) async throws -> T {
        let fileDescriptor = try openLockFile()
        defer { close(fileDescriptor) }

        try await acquireLock(fileDescriptor)
        defer { flock(fileDescriptor, LOCK_UN) }
        return try await body()
    }

    private nonisolated func openLockFile() throws -> Int32 {
        let containerURL = try baseURL ?? CodexSharedAppGroup.containerURL()
        let lockURL = containerURL
            .appending(path: CodexSharedAppGroup.lockFilename, directoryHint: .notDirectory)

        try FileManager.default.createDirectory(
            at: lockURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if !FileManager.default.fileExists(atPath: lockURL.path) {
            _ = FileManager.default.createFile(atPath: lockURL.path, contents: nil)
        }

        let fileDescriptor = open(lockURL.path, O_RDWR)
        guard fileDescriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        return fileDescriptor
    }

    private nonisolated func acquireLock(_ fileDescriptor: Int32) throws {
        while flock(fileDescriptor, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }

            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    private nonisolated func acquireLock(_ fileDescriptor: Int32) async throws {
        while flock(fileDescriptor, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }

            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}
