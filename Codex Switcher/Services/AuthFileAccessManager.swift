//
//  AuthFileAccessManager.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-07.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

struct AuthFileReadResult {
    let url: URL
    let contents: String
}

private struct AuthFileLocation {
    let scopeURL: URL
    let authFileURL: URL
}

@MainActor
protocol AuthFileManaging: AnyObject {
    func readAuthFile(promptIfNeeded: Bool) throws -> AuthFileReadResult
    func writeAuthFile(_ contents: String, promptIfNeeded: Bool) throws
}

enum AuthFileAccessError: LocalizedError {
    case accessRequired(URL)
    case invalidSelection
    case cancelled
    case missingAuthFile(URL)
    case unreadable(URL, underlying: Error)
    case unwritable(URL, underlying: Error)

    var errorDescription: String? {
        switch self {
        case let .accessRequired(url):
            "Codex Switcher needs permission to access \(url.path)."
        case .invalidSelection:
            "Please choose the hidden .codex folder."
        case .cancelled:
            "The file access request was cancelled."
        case .missingAuthFile:
            "Codex is currently logged out, so auth.json doesn't exist yet."
        case let .unreadable(url, _):
            "Codex Switcher couldn't read \(url.path)."
        case let .unwritable(url, _):
            "Codex Switcher couldn't write \(url.path)."
        }
    }

    var canRecoverByReprompting: Bool {
        switch self {
        case .unreadable, .unwritable:
            true
        case .accessRequired, .invalidSelection, .cancelled, .missingAuthFile:
            false
        }
    }

    var isMissingAuthFile: Bool {
        if case .missingAuthFile = self {
            true
        } else {
            false
        }
    }

    var isUserCancellation: Bool {
        if case .cancelled = self {
            true
        } else {
            false
        }
    }
}

@MainActor
final class SecurityScopedAuthFileManager: AuthFileManaging {
    private let defaults: UserDefaults
    private let fileManager: FileManager
    private let bookmarkKey = "CodexAuthFileBookmark"

    init(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        self.defaults = defaults
        self.fileManager = fileManager
    }

    func readAuthFile(promptIfNeeded: Bool) throws -> AuthFileReadResult {
        let hadStoredBookmark = defaults.data(forKey: bookmarkKey) != nil

        do {
            return try readAuthFileOnce(promptIfNeeded: promptIfNeeded)
        } catch let error as AuthFileAccessError
            where promptIfNeeded && hadStoredBookmark && error.canRecoverByReprompting
        {
            clearStoredBookmark()
            return try readAuthFileOnce(promptIfNeeded: true)
        }
    }

    func writeAuthFile(_ contents: String, promptIfNeeded: Bool) throws {
        let hadStoredBookmark = defaults.data(forKey: bookmarkKey) != nil

        do {
            try writeAuthFileOnce(contents, promptIfNeeded: promptIfNeeded)
        } catch let error as AuthFileAccessError
            where promptIfNeeded && hadStoredBookmark && error.canRecoverByReprompting
        {
            clearStoredBookmark()
            try writeAuthFileOnce(contents, promptIfNeeded: true)
        }
    }

    private func readAuthFileOnce(promptIfNeeded: Bool) throws -> AuthFileReadResult {
        let location = try resolveLocation(promptIfNeeded: promptIfNeeded)
        let authFileURL = location.authFileURL

        do {
            let contents = try withAuthorizedURL(location.scopeURL) { _ in
                guard fileManager.fileExists(atPath: authFileURL.path) else {
                    throw AuthFileAccessError.missingAuthFile(authFileURL)
                }

                return try String(contentsOf: authFileURL, encoding: .utf8)
            }
            return AuthFileReadResult(url: authFileURL, contents: contents)
        } catch let error as AuthFileAccessError {
            throw error
        } catch {
            if isMissingFileError(error) {
                throw AuthFileAccessError.missingAuthFile(authFileURL)
            }
            throw AuthFileAccessError.unreadable(authFileURL, underlying: error)
        }
    }

    private func writeAuthFileOnce(_ contents: String, promptIfNeeded: Bool) throws {
        let location = try resolveLocation(promptIfNeeded: promptIfNeeded)
        let authFileURL = location.authFileURL

        do {
            try withAuthorizedURL(location.scopeURL) { _ in
                let parent = authFileURL.deletingLastPathComponent()
                try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)

                let data = Data(contents.utf8)
                try data.write(to: authFileURL, options: [.atomic])
                try fileManager.setAttributes(
                    [.posixPermissions: NSNumber(value: Int16(0o600))],
                    ofItemAtPath: authFileURL.path
                )
            }

            // Refresh file-scoped bookmarks after atomic replacement so future
            // launches follow the current on-disk file rather than the old inode.
            if !location.scopeURL.hasDirectoryPath {
                try storeBookmark(for: location.scopeURL)
            }
        } catch {
            throw AuthFileAccessError.unwritable(authFileURL, underlying: error)
        }
    }

    private func resolveLocation(promptIfNeeded: Bool) throws -> AuthFileLocation {
        if let bookmarkedLocation = resolveBookmarkedLocation() {
            return bookmarkedLocation
        }

        if let directlyAccessibleLocation = directlyAccessibleDefaultLocation() {
            return directlyAccessibleLocation
        }

        guard promptIfNeeded else {
            throw AuthFileAccessError.accessRequired(defaultAuthFileURL)
        }

        return try promptForAuthLocation()
    }

    private var defaultAuthFileURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appending(component: ".codex", directoryHint: .isDirectory)
            .appending(component: "auth.json", directoryHint: .notDirectory)
    }

    private func resolveBookmarkedLocation() -> AuthFileLocation? {
        guard let bookmarkData = defaults.data(forKey: bookmarkKey) else {
            return nil
        }

        var isStale = false
        let url: URL
        do {
            url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            clearStoredBookmark()
            return nil
        }

        if isStale {
            do {
                try storeBookmark(for: url)
            } catch {
                clearStoredBookmark()
                return nil
            }
        }

        // Older builds could store a file-scoped bookmark to auth.json. Codex
        // replaces that file atomically, which can leave a file bookmark
        // pointing at a stale inode while the real auth.json changes elsewhere.
        // Drop those legacy bookmarks and force the app onto the .codex folder.
        guard url.hasDirectoryPath else {
            clearStoredBookmark()
            return nil
        }

        return location(forSelectedURL: url)
    }

    private func directlyAccessibleDefaultLocation() -> AuthFileLocation? {
        let authFileURL = defaultAuthFileURL
        let codexDirectoryURL = authFileURL.deletingLastPathComponent()

        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: codexDirectoryURL.path, isDirectory: &isDirectory),
           isDirectory.boolValue,
           fileManager.isReadableFile(atPath: codexDirectoryURL.path)
        {
            return AuthFileLocation(scopeURL: codexDirectoryURL, authFileURL: authFileURL)
        }

        guard fileManager.fileExists(atPath: authFileURL.path) else {
            return nil
        }

        guard fileManager.isReadableFile(atPath: authFileURL.path) else {
            return nil
        }

        return AuthFileLocation(scopeURL: authFileURL, authFileURL: authFileURL)
    }

    private func promptForAuthLocation() throws -> AuthFileLocation {
        let panel = NSOpenPanel()
        panel.prompt = "Allow Access"
        panel.message = "Choose the .codex folder."
        panel.directoryURL = fileManager.homeDirectoryForCurrentUser
        panel.allowedContentTypes = [.folder]
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        panel.showsHiddenFiles = true

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else {
            throw AuthFileAccessError.cancelled
        }

        guard let location = location(forSelectedURL: url) else {
            throw AuthFileAccessError.invalidSelection
        }

        try storeBookmark(for: location.scopeURL)
        return location
    }

    private func location(forSelectedURL url: URL) -> AuthFileLocation? {
        if url.hasDirectoryPath {
            guard url.lastPathComponent == ".codex" else {
                return nil
            }

            return AuthFileLocation(
                scopeURL: url,
                authFileURL: url.appending(component: "auth.json", directoryHint: .notDirectory)
            )
        }

        guard url.lastPathComponent == "auth.json" else {
            return nil
        }

        return AuthFileLocation(scopeURL: url, authFileURL: url)
    }

    private func storeBookmark(for url: URL) throws {
        let bookmark = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        defaults.set(bookmark, forKey: bookmarkKey)
    }

    private func clearStoredBookmark() {
        defaults.removeObject(forKey: bookmarkKey)
    }

    private func isMissingFileError(_ error: Error) -> Bool {
        let nsError = error as NSError

        if nsError.domain == NSCocoaErrorDomain {
            return nsError.code == NSFileNoSuchFileError || nsError.code == NSFileReadNoSuchFileError
        }

        if nsError.domain == NSPOSIXErrorDomain {
            return nsError.code == ENOENT
        }

        return false
    }

    private func withAuthorizedURL<T>(_ url: URL, perform operation: (URL) throws -> T) throws -> T {
        let startedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if startedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try operation(url)
    }
}
