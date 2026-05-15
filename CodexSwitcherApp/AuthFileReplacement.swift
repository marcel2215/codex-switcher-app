//
//  AuthFileReplacement.swift
//  Codex Switcher
//
//  Created by Marcel Kwiatkowski on 2026-04-24.
//

import Foundation

#if canImport(Darwin)
import Darwin
#endif

enum CodexAuthFileReplacementError: LocalizedError, Equatable {
    case invalidFileDescriptor
    case posixFailure(operation: String, code: Int32)
    case insecurePermissions(URL, mode: Int)

    var errorDescription: String? {
        switch self {
        case .invalidFileDescriptor:
            L10n.string("authFileReplacement.error.invalidFileDescriptor", defaultValue: "Codex Switcher couldn't create a temporary auth file.")
        case let .posixFailure(operation, code):
            L10n.string(
                "authFileReplacement.error.posixFailure",
                defaultValue: "Codex Switcher couldn't %@ auth.json securely (errno %d).",
                operation,
                code
            )
        case let .insecurePermissions(url, mode):
            L10n.string(
                "authFileReplacement.error.insecurePermissions",
                defaultValue: "Codex Switcher wrote %@, but couldn't restrict it to owner-only permissions (mode %@).",
                url.path,
                String(mode, radix: 8)
            )
        }
    }
}

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
            try writeRestrictedTemporaryFile(Data(contents.utf8), to: temporaryURL, fileManager: fileManager)

            if fileManager.fileExists(atPath: authFileURL.path) {
                _ = try fileManager.replaceItemAt(
                    authFileURL,
                    withItemAt: temporaryURL,
                    backupItemName: nil,
                    options: [.usingNewMetadataOnly]
                )
            } else {
                try fileManager.moveItem(at: temporaryURL, to: authFileURL)
            }

            try enforceRestrictivePermissions(at: authFileURL, fileManager: fileManager)
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    private nonisolated static func writeRestrictedTemporaryFile(
        _ data: Data,
        to temporaryURL: URL,
        fileManager: FileManager
    ) throws {
#if canImport(Darwin)
        let path = temporaryURL.path
        var fileDescriptor = open(path, O_CREAT | O_EXCL | O_WRONLY, S_IRUSR | S_IWUSR)
        guard fileDescriptor >= 0 else {
            throw CodexAuthFileReplacementError.posixFailure(operation: "open", code: errno)
        }

        do {
            try data.withUnsafeBytes { rawBuffer in
                guard let baseAddress = rawBuffer.baseAddress else {
                    return
                }

                var remainingBytes = rawBuffer.count
                var currentAddress = baseAddress

                while remainingBytes > 0 {
                    let writtenByteCount = write(fileDescriptor, currentAddress, remainingBytes)
                    if writtenByteCount < 0 {
                        if errno == EINTR {
                            continue
                        }

                        throw CodexAuthFileReplacementError.posixFailure(operation: "write", code: errno)
                    }

                    guard writtenByteCount > 0 else {
                        throw CodexAuthFileReplacementError.posixFailure(operation: "write", code: EIO)
                    }

                    remainingBytes -= writtenByteCount
                    currentAddress = currentAddress.advanced(by: writtenByteCount)
                }
            }

            if fsync(fileDescriptor) != 0 {
                throw CodexAuthFileReplacementError.posixFailure(operation: "flush", code: errno)
            }

            if close(fileDescriptor) != 0 {
                fileDescriptor = -1
                throw CodexAuthFileReplacementError.posixFailure(operation: "close", code: errno)
            }

            fileDescriptor = -1
        } catch {
            if fileDescriptor >= 0 {
                _ = close(fileDescriptor)
            }
            throw error
        }
#else
        try data.write(to: temporaryURL, options: [.withoutOverwriting])
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: temporaryURL.path
        )
#endif
    }

    private nonisolated static func enforceRestrictivePermissions(
        at authFileURL: URL,
        fileManager: FileManager
    ) throws {
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: authFileURL.path
        )

        let attributes = try fileManager.attributesOfItem(atPath: authFileURL.path)
        let mode = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
        guard mode & 0o777 == 0o600 else {
            throw CodexAuthFileReplacementError.insecurePermissions(authFileURL, mode: mode)
        }
    }
}
