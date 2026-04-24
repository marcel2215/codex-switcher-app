//
//  AuthFileReplacement.swift
//  Codex Switcher
//
//  Created by Marcel Kwiatkowski on 2026-04-24.
//

import Foundation

enum CodexAuthFileReplacement {
    nonisolated static func replaceContents(
        _ contents: String,
        at authFileURL: URL,
        fileManager: FileManager = .default
    ) throws {
        let directoryURL = authFileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let temporaryURL = directoryURL.appending(
            path: ".auth.json.\(UUID().uuidString).tmp",
            directoryHint: .notDirectory
        )

        do {
            try Data(contents.utf8).write(to: temporaryURL, options: [.atomic])

            if fileManager.fileExists(atPath: authFileURL.path) {
                _ = try fileManager.replaceItemAt(
                    authFileURL,
                    withItemAt: temporaryURL,
                    backupItemName: nil,
                    options: []
                )
            } else {
                try fileManager.moveItem(at: temporaryURL, to: authFileURL)
            }

            try? fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: Int16(0o600))],
                ofItemAtPath: authFileURL.path
            )
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }
}
