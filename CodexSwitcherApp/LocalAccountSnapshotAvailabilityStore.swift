//
//  LocalAccountSnapshotAvailabilityStore.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-15.
//

import Foundation

/// Tracks which accounts currently have a usable local auth snapshot on this
/// device. This intentionally stays out of SwiftData + CloudKit because
/// snapshot presence is device-local state and syncing it creates cross-device
/// churn that can overwrite real metadata changes.
struct LocalAccountSnapshotAvailabilityStore: Sendable {
    private let baseURL: URL?

    nonisolated init(baseURL: URL? = nil) {
        self.baseURL = baseURL
    }

    nonisolated func containsSnapshot(forIdentityKey identityKey: String) -> Bool {
        guard let normalizedIdentityKey = normalizedIdentityKey(identityKey) else {
            return false
        }

        return (try? loadIdentityKeys().contains(normalizedIdentityKey)) ?? false
    }

    nonisolated func setSnapshotAvailable(_ isAvailable: Bool, forIdentityKey identityKey: String) {
        guard let normalizedIdentityKey = normalizedIdentityKey(identityKey) else {
            return
        }

        do {
            var identityKeys = try loadIdentityKeys()
            if isAvailable {
                identityKeys.insert(normalizedIdentityKey)
            } else {
                identityKeys.remove(normalizedIdentityKey)
            }

            try saveIdentityKeys(identityKeys)
        } catch {
            return
        }
    }

    private nonisolated func normalizedIdentityKey(_ identityKey: String) -> String? {
        let normalizedIdentityKey = identityKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedIdentityKey.isEmpty else {
            return nil
        }

        return normalizedIdentityKey
    }

    private nonisolated func loadIdentityKeys() throws -> Set<String> {
        let fileURL = try fileURL()
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(Set<String>.self, from: data)
    }

    private nonisolated func saveIdentityKeys(_ identityKeys: Set<String>) throws {
        let fileURL = try fileURL()
        let directoryURL = fileURL.deletingLastPathComponent()

        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(identityKeys)
        try data.write(to: fileURL, options: [.atomic])

#if os(iOS) || os(watchOS) || os(tvOS)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: fileURL.path
        )
#endif
    }

    private nonisolated func fileURL() throws -> URL {
        let containerURL = try baseURL ?? CodexSharedAppGroup.containerURL()
        return containerURL.appending(
            path: CodexSharedAppGroup.snapshotAvailabilityFilename,
            directoryHint: .notDirectory
        )
    }
}
