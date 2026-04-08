//
//  AuthFileAccessManager.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-08.
//

import Foundation
import OSLog
import Dispatch

#if canImport(Darwin)
import Darwin
#endif

struct AuthFileReadResult: Sendable, Equatable {
    nonisolated let url: URL
    nonisolated let contents: String
}

struct AuthLinkedLocation: Sendable, Equatable {
    nonisolated let folderURL: URL
    nonisolated let credentialStoreHint: CodexCredentialStoreHint

    nonisolated var authFileURL: URL {
        folderURL.appending(path: "auth.json", directoryHint: .notDirectory)
    }

    nonisolated var configFileURL: URL {
        folderURL.appending(path: "config.toml", directoryHint: .notDirectory)
    }
}

enum CodexCredentialStoreHint: String, Sendable, Equatable {
    case unknown
    case file
    case keyring
    case auto

    nonisolated var isSupportedForFileSwitching: Bool {
        switch self {
        case .unknown, .file:
            true
        case .keyring, .auto:
            false
        }
    }

    nonisolated var displayName: String {
        switch self {
        case .unknown:
            "unknown"
        case .file:
            "file"
        case .keyring:
            "keyring"
        case .auto:
            "auto"
        }
    }
}

protocol AuthFileManaging: AnyObject {
    func linkedLocation() async -> AuthLinkedLocation?
    func linkLocation(_ selectedURL: URL) async throws -> AuthLinkedLocation
    func clearLinkedLocation() async
    func readAuthFile() async throws -> AuthFileReadResult
    func writeAuthFile(_ contents: String) async throws
    func startMonitoring(_ onChange: @escaping @Sendable () -> Void) async
}

enum AuthFileAccessError: LocalizedError, Equatable {
    case accessRequired
    case invalidSelection
    case cancelled
    case missingAuthFile(URL, credentialStoreHint: CodexCredentialStoreHint)
    case locationUnavailable(URL)
    case accessDenied(URL)
    case unsupportedCredentialStore(URL, mode: CodexCredentialStoreHint)
    case unreadable(URL, message: String)
    case unwritable(URL, message: String)
    case verificationFailed(URL)

    var errorDescription: String? {
        switch self {
        case .accessRequired:
            "Choose the Codex folder before switching accounts."
        case .invalidSelection:
            "Choose the Codex folder that contains auth.json."
        case .cancelled:
            "The file access request was cancelled."
        case let .missingAuthFile(url, _):
            "No auth.json was found in \(url.deletingLastPathComponent().path)."
        case let .locationUnavailable(url):
            "The linked Codex folder is no longer available: \(url.path)."
        case let .accessDenied(url):
            "Codex Switcher no longer has permission to access \(url.path)."
        case let .unsupportedCredentialStore(url, mode):
            "The linked Codex folder at \(url.path) is configured for \(mode.displayName) credential storage. Codex Switcher only supports file-backed auth.json switching."
        case let .unreadable(url, message):
            "Codex Switcher couldn't read \(url.path). \(message)"
        case let .unwritable(url, message):
            "Codex Switcher couldn't write \(url.path). \(message)"
        case let .verificationFailed(url):
            "Codex Switcher wrote \(url.path), but the verification readback did not match the saved account."
        }
    }

    var isUserCancellation: Bool {
        if case .cancelled = self {
            return true
        }

        return false
    }
}

actor SecurityScopedAuthFileManager: AuthFileManaging {
    private let defaults: UserDefaults = .standard
    private let fileManager: FileManager = .default
    private let bookmarkKey = "CodexLinkedFolderBookmark"
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "CodexSwitcher",
        category: "AuthFileManager"
    )
    private let watcher = AuthDirectoryWatcher()
    private var onChange: (@Sendable () -> Void)?

    func linkedLocation() async -> AuthLinkedLocation? {
        guard let folderURL = await resolveLinkedFolderURLIfAvailable() else {
            return nil
        }

        let credentialStoreHint = (try? credentialStoreHint(for: folderURL)) ?? .unknown
        return AuthLinkedLocation(folderURL: folderURL, credentialStoreHint: credentialStoreHint)
    }

    private func resolveLinkedFolderURLIfAvailable() async -> URL? {
        do {
            return try resolveLinkedFolderURL()
        } catch {
            logger.error("Failed to resolve linked folder: \(String(describing: error), privacy: .private)")
            clearStoredBookmark()
            await watcher.stop()
            return nil
        }
    }

    func linkLocation(_ selectedURL: URL) async throws -> AuthLinkedLocation {
        let linkedLocation = try withSelectedLocationAuthorization(selectedURL) { selectedURL in
            let folderURL = try normalizedFolderURL(from: selectedURL)

            do {
                try storeBookmark(for: folderURL)
            } catch {
                logger.error("Failed to store bookmark for linked folder: \(String(describing: error), privacy: .private)")
                throw AuthFileAccessError.accessDenied(folderURL)
            }

            return try location(forFolderURL: folderURL)
        }
        await restartMonitoringIfPossible()
        return linkedLocation
    }

    func clearLinkedLocation() async {
        clearStoredBookmark()
        await watcher.stop()
    }

    func readAuthFile() async throws -> AuthFileReadResult {
        let location = try await requireLinkedLocation()
        try ensureSupportedCredentialStore(for: location)

        return try withFolderAuthorization(for: location.folderURL) { [fileManager] folderURL in
            let authFileURL = folderURL.appending(path: "auth.json", directoryHint: .notDirectory)

            guard fileManager.fileExists(atPath: authFileURL.path) else {
                throw AuthFileAccessError.missingAuthFile(authFileURL, credentialStoreHint: location.credentialStoreHint)
            }

            return try coordinatedRead(of: authFileURL)
        }
    }

    func writeAuthFile(_ contents: String) async throws {
        let location = try await requireLinkedLocation()
        try ensureSupportedCredentialStore(for: location)

        try withFolderAuthorization(for: location.folderURL) { [fileManager] folderURL in
            guard directoryExists(at: folderURL) else {
                throw AuthFileAccessError.locationUnavailable(folderURL)
            }

            let authFileURL = folderURL.appending(path: "auth.json", directoryHint: .notDirectory)
            try coordinatedWrite(contents, to: authFileURL)

            let verifiedRead = try coordinatedRead(of: authFileURL)
            guard verifiedRead.contents == contents else {
                throw AuthFileAccessError.verificationFailed(authFileURL)
            }

            // Mirror Codex's restrictive file mode without assuming the file
            // already existed before this write.
            try? fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: Int16(0o600))],
                ofItemAtPath: authFileURL.path
            )
        }
    }

    func startMonitoring(_ onChange: @escaping @Sendable () -> Void) async {
        self.onChange = onChange
        await restartMonitoringIfPossible()
    }

    private func requireLinkedLocation() async throws -> AuthLinkedLocation {
        guard let folderURL = await resolveLinkedFolderURLIfAvailable() else {
            throw AuthFileAccessError.accessRequired
        }

        let hint = (try? credentialStoreHint(for: folderURL)) ?? .unknown
        return AuthLinkedLocation(folderURL: folderURL, credentialStoreHint: hint)
    }

    private func resolveLinkedFolderURL() throws -> URL {
        guard let bookmarkData = defaults.data(forKey: bookmarkKey) else {
            throw AuthFileAccessError.accessRequired
        }

        var isStale = false
        let folderURL = try URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope, .withoutImplicitStartAccessing, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ).standardizedFileURL

        if isStale {
            try storeBookmark(for: folderURL)
        }

        return folderURL
    }

    private func normalizedFolderURL(from selectedURL: URL) throws -> URL {
        let standardizedURL = selectedURL.standardizedFileURL

        if isDirectoryURL(standardizedURL) {
            return standardizedURL
        }

        throw AuthFileAccessError.invalidSelection
    }

    private func withSelectedLocationAuthorization<T>(_ selectedURL: URL, _ body: (URL) throws -> T) throws -> T {
        let started = selectedURL.startAccessingSecurityScopedResource()
        defer {
            if started {
                selectedURL.stopAccessingSecurityScopedResource()
            }
        }

        return try body(selectedURL)
    }

    private func location(forFolderURL folderURL: URL) throws -> AuthLinkedLocation {
        let hint = try credentialStoreHint(for: folderURL)
        return AuthLinkedLocation(folderURL: folderURL, credentialStoreHint: hint)
    }

    private func credentialStoreHint(for folderURL: URL) throws -> CodexCredentialStoreHint {
        try withFolderAuthorization(for: folderURL) { folderURL in
            let configURL = folderURL.appending(path: "config.toml", directoryHint: .notDirectory)
            guard let contents = try? String(contentsOf: configURL, encoding: .utf8) else {
                return .unknown
            }

            // Codex config is TOML. We only need one scalar key here, so a
            // lightweight regex keeps the dependency surface small.
            let pattern = #"(?m)^\s*cli_auth_credentials_store\s*=\s*"([^"]+)""#
            guard
                let regex = try? NSRegularExpression(pattern: pattern),
                let match = regex.firstMatch(
                    in: contents,
                    range: NSRange(contents.startIndex..., in: contents)
                ),
                let valueRange = Range(match.range(at: 1), in: contents)
            else {
                return .unknown
            }

            return CodexCredentialStoreHint(rawValue: String(contents[valueRange]).lowercased()) ?? .unknown
        }
    }

    private func ensureSupportedCredentialStore(for location: AuthLinkedLocation) throws {
        guard location.credentialStoreHint.isSupportedForFileSwitching else {
            throw AuthFileAccessError.unsupportedCredentialStore(
                location.folderURL,
                mode: location.credentialStoreHint
            )
        }
    }

    private func storeBookmark(for folderURL: URL) throws {
        let bookmark = try folderURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        defaults.set(bookmark, forKey: bookmarkKey)
    }

    private func clearStoredBookmark() {
        defaults.removeObject(forKey: bookmarkKey)
    }

    private func restartMonitoringIfPossible() async {
        await watcher.stop()

        guard let onChange else {
            return
        }

        guard let folderURL = await resolveLinkedFolderURLIfAvailable() else {
            return
        }

        do {
            try await watcher.start(directoryURL: folderURL, onEvent: onChange)
        } catch {
            logger.error("Failed to start directory watcher: \(String(describing: error), privacy: .private)")
        }
    }

    private func withFolderAuthorization<T>(for folderURL: URL, _ body: (URL) throws -> T) throws -> T {
        let started = folderURL.startAccessingSecurityScopedResource()
        guard started else {
            throw AuthFileAccessError.accessDenied(folderURL)
        }

        defer { folderURL.stopAccessingSecurityScopedResource() }
        guard directoryExists(at: folderURL) else {
            throw AuthFileAccessError.locationUnavailable(folderURL)
        }

        return try body(folderURL)
    }

    private func coordinatedRead(of authFileURL: URL) throws -> AuthFileReadResult {
        var coordinationError: NSError?
        var readContents: String?
        var readError: Error?

        NSFileCoordinator().coordinate(readingItemAt: authFileURL, options: [], error: &coordinationError) { url in
            do {
                readContents = try String(contentsOf: url, encoding: .utf8)
            } catch {
                readError = error
            }
        }

        if let coordinationError {
            if isMissingFileError(coordinationError) {
                throw AuthFileAccessError.missingAuthFile(authFileURL, credentialStoreHint: .unknown)
            }
            throw AuthFileAccessError.unreadable(authFileURL, message: coordinationError.localizedDescription)
        }

        if let readError {
            if isMissingFileError(readError) {
                throw AuthFileAccessError.missingAuthFile(authFileURL, credentialStoreHint: .unknown)
            }
            throw AuthFileAccessError.unreadable(authFileURL, message: readError.localizedDescription)
        }

        guard let readContents else {
            throw AuthFileAccessError.unreadable(authFileURL, message: "The file coordinator returned no contents.")
        }

        return AuthFileReadResult(url: authFileURL, contents: readContents)
    }

    private func coordinatedWrite(_ contents: String, to authFileURL: URL) throws {
        var coordinationError: NSError?
        var writeError: Error?
        let data = Data(contents.utf8)

        NSFileCoordinator().coordinate(writingItemAt: authFileURL, options: [], error: &coordinationError) { url in
            do {
                try data.write(to: url, options: [.atomic])
            } catch {
                writeError = error
            }
        }

        if let coordinationError {
            throw AuthFileAccessError.unwritable(authFileURL, message: coordinationError.localizedDescription)
        }

        if let writeError {
            throw AuthFileAccessError.unwritable(authFileURL, message: writeError.localizedDescription)
        }
    }

    private func directoryExists(at folderURL: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: folderURL.path, isDirectory: &isDirectory) else {
            return false
        }

        return isDirectory.boolValue
    }

    private func isDirectoryURL(_ url: URL) -> Bool {
        if let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey]),
           resourceValues.isDirectory == true {
            return true
        }

        return directoryExists(at: url)
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
}

private actor AuthDirectoryWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: CInt = -1
    private var monitoredURL: URL?
    private var isAccessingSecurityScope = false

    func start(directoryURL: URL, onEvent: @escaping @Sendable () -> Void) throws {
        stop()

        let startedAccess = directoryURL.startAccessingSecurityScopedResource()
        guard startedAccess else {
            throw AuthFileAccessError.accessDenied(directoryURL)
        }

        let descriptor = open(directoryURL.path, O_EVTONLY)
        guard descriptor >= 0 else {
            directoryURL.stopAccessingSecurityScopedResource()
            throw POSIXError(.EIO)
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .revoke],
            queue: DispatchQueue.global(qos: .utility)
        )

        source.setEventHandler(handler: onEvent)
        source.setCancelHandler { [descriptor, directoryURL] in
            close(descriptor)
            directoryURL.stopAccessingSecurityScopedResource()
        }
        source.activate()

        self.source = source
        self.fileDescriptor = descriptor
        self.monitoredURL = directoryURL
        self.isAccessingSecurityScope = true
    }

    func stop() {
        if let source {
            source.cancel()
            self.source = nil
        } else if isAccessingSecurityScope, let monitoredURL {
            monitoredURL.stopAccessingSecurityScopedResource()
        }

        fileDescriptor = -1
        monitoredURL = nil
        isAccessingSecurityScope = false
    }
}
