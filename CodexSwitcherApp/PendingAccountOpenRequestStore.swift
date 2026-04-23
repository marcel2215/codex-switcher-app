//
//  PendingAccountOpenRequestStore.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-16.
//

import Foundation

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
            try data.write(to: requestFileURL(), options: [.atomic])
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

            let request = try JSONDecoder().decode(CodexPendingAccountOpenRequest.self, from: data)
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
