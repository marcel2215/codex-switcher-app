//
//  CodexSharedAppCommandResultStore.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-10.
//

import Foundation

enum CodexSharedAppCommandResultStatus: String, Codable, Equatable, Sendable {
    case success
    case failure
}

struct CodexSharedAppCommandResult: Codable, Equatable, Sendable {
    let commandID: UUID
    let status: CodexSharedAppCommandResultStatus
    let message: String?
    let accountIdentityKey: String?
    let completedAt: Date

    nonisolated init(
        commandID: UUID,
        status: CodexSharedAppCommandResultStatus,
        message: String? = nil,
        accountIdentityKey: String? = nil,
        completedAt: Date = .now
    ) {
        self.commandID = commandID
        self.status = status
        self.message = message?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.accountIdentityKey = accountIdentityKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.completedAt = completedAt
    }
}

enum CodexSharedIntentExecutionError: LocalizedError {
    case commandTimedOut(UUID)
    case commandFailed(String)

    nonisolated var errorDescription: String? {
        switch self {
        case .commandTimedOut:
            return "Codex Switcher didn't finish the requested action in time."
        case let .commandFailed(message):
            return message
        }
    }
}

struct CodexSharedAppCommandResultStore: Sendable {
    private let baseURL: URL?
    private let lock: CodexSharedProcessLock

    nonisolated init(
        baseURL: URL? = nil,
        lock: CodexSharedProcessLock? = nil
    ) {
        self.baseURL = baseURL
        self.lock = lock ?? CodexSharedProcessLock(baseURL: baseURL)
    }

    nonisolated func save(_ result: CodexSharedAppCommandResult) throws {
        try lock.withExclusiveAccess {
            let fileURL = try resultsFileURL()
            var results = try loadAllUnlocked(from: fileURL)
            pruneExpiredResults(from: &results)
            results[result.commandID] = result
            try saveAllUnlocked(results, to: fileURL)
        }
    }

    nonisolated func load(commandID: UUID) throws -> CodexSharedAppCommandResult? {
        try lock.withExclusiveAccess {
            let results = try loadAllUnlocked(from: resultsFileURL())
            return results[commandID]
        }
    }

    nonisolated func remove(commandID: UUID) throws {
        try lock.withExclusiveAccess {
            let fileURL = try resultsFileURL()
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return
            }

            var results = try loadAllUnlocked(from: fileURL)
            results.removeValue(forKey: commandID)
            try saveAllUnlocked(results, to: fileURL)
        }
    }

    nonisolated func waitForResult(
        commandID: UUID,
        timeoutNanoseconds: UInt64 = 20_000_000_000,
        pollNanoseconds: UInt64 = 200_000_000
    ) async throws -> CodexSharedAppCommandResult {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds

        while DispatchTime.now().uptimeNanoseconds < deadline {
            if let result = try load(commandID: commandID) {
                return result
            }

            try await Task.sleep(nanoseconds: pollNanoseconds)
        }

        throw CodexSharedIntentExecutionError.commandTimedOut(commandID)
    }

    private nonisolated func resultsFileURL() throws -> URL {
        let containerURL = try baseURL ?? CodexSharedAppGroup.containerURL()
        return containerURL.appending(
            path: CodexSharedAppGroup.appCommandResultFilename,
            directoryHint: .notDirectory
        )
    }

    private nonisolated func loadAllUnlocked(
        from fileURL: URL
    ) throws -> [UUID: CodexSharedAppCommandResult] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return [:]
        }

        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            return [:]
        }

        return try JSONDecoder().decode([UUID: CodexSharedAppCommandResult].self, from: data)
    }

    private nonisolated func saveAllUnlocked(
        _ results: [UUID: CodexSharedAppCommandResult],
        to fileURL: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(results)
        try data.write(to: fileURL, options: [.atomic])
    }

    private nonisolated func pruneExpiredResults(
        from results: inout [UUID: CodexSharedAppCommandResult]
    ) {
        let expirationDate = Date().addingTimeInterval(-24 * 60 * 60)
        results = results.filter { $0.value.completedAt >= expirationDate }
    }
}
