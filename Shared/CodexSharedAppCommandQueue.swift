//
//  CodexSharedAppCommandQueue.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-10.
//

import Foundation

#if canImport(AppKit)
import AppKit
#endif

enum CodexSharedAppCommandAction: String, Codable, Sendable {
    case captureCurrentAccount
    case switchAccount
    case switchBestAccount
    case removeAccount
    case quitApplication
}

struct CodexSharedAppCommand: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let action: CodexSharedAppCommandAction
    let accountIdentityKey: String?
    let targetProcess: CodexSharedAppProcessIdentity?
    let expectsResult: Bool
    let requestedAt: Date

    nonisolated init(
        id: UUID = UUID(),
        action: CodexSharedAppCommandAction,
        accountIdentityKey: String? = nil,
        targetProcess: CodexSharedAppProcessIdentity? = nil,
        expectsResult: Bool = false,
        requestedAt: Date = .now
    ) {
        self.id = id
        self.action = action
        self.accountIdentityKey = accountIdentityKey?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.targetProcess = targetProcess
        self.expectsResult = expectsResult
        self.requestedAt = requestedAt
    }

    enum QuitRoutingDecision: Equatable, Sendable {
        case terminateCurrentProcess
        case waitForTargetProcess
        case discardStaleCommand
    }

    /// Targeted quit commands allow a newer app instance to ask one older
    /// instance to exit without accidentally consuming the command itself.
    nonisolated func quitRoutingDecision(
        currentProcess: CodexSharedAppProcessIdentity,
        runningProcesses: [CodexSharedAppProcessIdentity]
    ) -> QuitRoutingDecision {
        guard let targetProcess else {
            return .terminateCurrentProcess
        }

        if targetProcess == currentProcess {
            return .terminateCurrentProcess
        }

        return runningProcesses.contains(targetProcess)
            ? .waitForTargetProcess
            : .discardStaleCommand
    }
}

struct CodexSharedAppCommandQueue: Sendable {
    private let baseURL: URL?
    private let lock: CodexSharedProcessLock

    nonisolated init(
        baseURL: URL? = nil,
        lock: CodexSharedProcessLock? = nil
    ) {
        self.baseURL = baseURL
        self.lock = lock ?? CodexSharedProcessLock(baseURL: baseURL)
    }

    /// Queue app-owned work that an extension cannot safely perform directly,
    /// such as SwiftData mutations or terminating the main process.
    nonisolated func enqueue(_ command: CodexSharedAppCommand) throws {
        try lock.withExclusiveAccess {
            let fileURL = try commandsFileURL()
            var commands = try loadCommandsUnlocked(from: fileURL)
            commands.append(command)
            try saveCommandsUnlocked(commands, to: fileURL)
        }
    }

    nonisolated func load() throws -> [CodexSharedAppCommand] {
        try lock.withExclusiveAccess {
            let commands = try loadCommandsUnlocked(from: commandsFileURL())
            return commands.sorted { $0.requestedAt < $1.requestedAt }
        }
    }

    /// Remove one command only after the main app has actually handled it, so
    /// app-owned work survives crashes between dequeue and completion.
    nonisolated func removeCommand(id commandID: UUID) throws {
        try lock.withExclusiveAccess {
            let fileURL = try commandsFileURL()
            let commands = try loadCommandsUnlocked(from: fileURL)
                .filter { $0.id != commandID }
            try saveCommandsUnlocked(commands, to: fileURL)
        }
    }

    private nonisolated func loadCommandsUnlocked(from fileURL: URL) throws -> [CodexSharedAppCommand] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            return []
        }

        return try JSONDecoder().decode([CodexSharedAppCommand].self, from: data)
    }

    private nonisolated func saveCommandsUnlocked(
        _ commands: [CodexSharedAppCommand],
        to fileURL: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(commands)
        try data.write(to: fileURL, options: [.atomic])
    }

    private nonisolated func commandsFileURL() throws -> URL {
        let containerURL = try baseURL ?? CodexSharedAppGroup.containerURL()
        return containerURL.appending(path: CodexSharedAppGroup.appCommandFilename, directoryHint: .notDirectory)
    }
}

enum CodexSharedAppCommandSignal {
    nonisolated static let didEnqueueCommandNotification = Notification.Name(
        "com.marcel2215.codexswitcher.didEnqueueAppCommand"
    )

    nonisolated static let mainApplicationBundleIdentifier = CodexSharedApplicationIdentity.mainApplicationBundleIdentifier

    nonisolated static func postCommandQueuedSignal() {
        DistributedNotificationCenter.default().post(
            name: didEnqueueCommandNotification,
            object: nil,
            userInfo: nil
        )
    }

    nonisolated static var isMainApplicationRunning: Bool {
        #if canImport(AppKit)
        !NSRunningApplication.runningApplications(
            withBundleIdentifier: mainApplicationBundleIdentifier
        ).isEmpty
        #else
        false
        #endif
    }
}
