//
//  PendingAccountOpenRequestStore.swift
//  Codex Switcher
//
//  Created by Marcel Kwiatkowski on 2026-04-16.
//

import Foundation
import OSLog

#if canImport(AppKit)
import AppKit
#endif

nonisolated struct CodexPendingAccountOpenRequest: Codable, Equatable, Sendable {
    let identityKey: String
    let requestedAt: Date

    nonisolated init(identityKey: String, requestedAt: Date = .now) {
        self.identityKey = identityKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.requestedAt = requestedAt
    }
}

nonisolated struct CodexPendingAccountOpenRequestStore: Sendable {
    private let baseURL: URL?
    private let lock: CodexSharedProcessLock
    private let logger = Logger(
        subsystem: CodexSharedApplicationIdentity.mainApplicationBundleIdentifier,
        category: "PendingAccountOpenRequestStore"
    )

    nonisolated init(
        baseURL: URL? = nil,
        lock: CodexSharedProcessLock? = nil
    ) {
        self.baseURL = baseURL
        self.lock = lock ?? CodexSharedProcessLock(baseURL: baseURL)
    }

    /// Spotlight/OpenIntent requests must survive the handoff between the
    /// intent process and the main app process. Persist one request at a time:
    /// the most recent user selection is the only one that still matters.
    nonisolated func save(identityKey: String) throws {
        let request = CodexPendingAccountOpenRequest(identityKey: identityKey)
        guard !request.identityKey.isEmpty else {
            throw CodexPendingAccountOpenRequestError.missingIdentityKey
        }

        try lock.withExclusiveAccess {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(request)
            let fileURL = try requestFileURL()
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: [.atomic])
            try CodexSharedFileProtection.apply(to: fileURL)
        }
    }

    nonisolated func consume() throws -> CodexPendingAccountOpenRequest? {
        try lock.withExclusiveAccess {
            let fileURL = try requestFileURL()
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return nil
            }

            defer {
                try? FileManager.default.removeItem(at: fileURL)
            }

            let data = try Data(contentsOf: fileURL)
            guard !data.isEmpty else {
                return nil
            }

            let request: CodexPendingAccountOpenRequest
            do {
                request = try JSONDecoder().decode(CodexPendingAccountOpenRequest.self, from: data)
            } catch {
                do {
                    let backupURL = try CodexCorruptSharedFileQuarantine.moveAside(
                        fileURL,
                        reason: "open-request"
                    )
                    logger.error(
                        "Quarantined corrupt pending account-open request at \(backupURL.path, privacy: .private): \(String(describing: error), privacy: .private)"
                    )
                } catch {
                    logger.error(
                        "Couldn't quarantine corrupt pending account-open request: \(String(describing: error), privacy: .private)"
                    )
                    throw error
                }
                return nil
            }

            return request.identityKey.isEmpty ? nil : request
        }
    }

    private nonisolated func requestFileURL() throws -> URL {
        let containerURL = try baseURL ?? CodexSharedAppGroup.containerURL()
        return containerURL.appending(
            path: CodexSharedAppGroup.pendingAccountOpenFilename,
            directoryHint: .notDirectory
        )
    }
}

nonisolated enum CodexPendingAccountOpenRequestError: LocalizedError {
    case missingIdentityKey

    nonisolated var errorDescription: String? {
        switch self {
        case .missingIdentityKey:
            return "Codex Switcher couldn't determine which saved account to open."
        }
    }
}

nonisolated enum CodexPendingAccountOpenSignal {
    nonisolated static let didRequestOpenAccountNotification = Notification.Name(
        "com.marcel2215.codexswitcher.didRequestOpenAccount"
    )

    nonisolated static func postRequestQueuedSignal() {
#if os(macOS)
        DistributedNotificationCenter.default().post(
            name: didRequestOpenAccountNotification,
            object: nil,
            userInfo: nil
        )
#else
        NotificationCenter.default.post(
            name: didRequestOpenAccountNotification,
            object: nil
        )
#endif
    }
}
