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

enum CodexSharedProcessLockError: LocalizedError, Equatable {
    case timedOut

    nonisolated var errorDescription: String? {
        switch self {
        case .timedOut:
            "Timed out waiting for Codex Switcher shared storage."
        }
    }
}

struct CodexSharedProcessLock: Sendable {
    nonisolated private static let defaultTimeout: TimeInterval = 5
    nonisolated private static let defaultAsyncTimeout: Duration = .seconds(5)
    private let baseURL: URL?
    private let timeout: TimeInterval
    private let asyncTimeout: Duration

    nonisolated init(
        baseURL: URL? = nil,
        timeout: TimeInterval = Self.defaultTimeout,
        asyncTimeout: Duration = Self.defaultAsyncTimeout
    ) {
        self.baseURL = baseURL
        self.timeout = timeout
        self.asyncTimeout = asyncTimeout
    }

    nonisolated func withExclusiveAccess<T>(_ body: () throws -> T) throws -> T {
        let fileDescriptor = try openLockFile()
        defer { close(fileDescriptor) }

        try acquireLock(fileDescriptor, timeout: timeout)
        defer { flock(fileDescriptor, LOCK_UN) }
        return try body()
    }

    nonisolated func withExclusiveAccess<T>(_ body: () async throws -> T) async throws -> T {
        let fileDescriptor = try openLockFile()
        defer { close(fileDescriptor) }

        try await acquireLock(fileDescriptor, timeout: asyncTimeout)
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

    private nonisolated func acquireLock(
        _ fileDescriptor: Int32,
        timeout: TimeInterval
    ) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while flock(fileDescriptor, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }

            guard Date() < deadline else {
                throw CodexSharedProcessLockError.timedOut
            }

            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    private nonisolated func acquireLock(
        _ fileDescriptor: Int32,
        timeout: Duration
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while flock(fileDescriptor, LOCK_EX | LOCK_NB) != 0 {
            try Task.checkCancellation()

            guard errno == EWOULDBLOCK else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }

            guard clock.now < deadline else {
                throw CodexSharedProcessLockError.timedOut
            }

            try await Task.sleep(for: .milliseconds(50))
        }
    }
}
