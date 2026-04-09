//
//  CodexSharedAccountSwitchService.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-08.
//

import Foundation

#if canImport(Darwin)
import Darwin
#endif

enum CodexSharedSwitchError: LocalizedError {
    case accountSelectionRequired
    case accountNotFound(String)
    case missingStoredSnapshot(String)
    case invalidStoredSnapshot(String)
    case missingBookmark
    case unsupportedAuthState(SharedCodexAuthState)
    case accessDenied(URL)
    case linkedFolderUnavailable(URL)
    case unreadable(URL, message: String)
    case unwritable(URL, message: String)
    case verificationFailed(URL)

    nonisolated var errorDescription: String? {
        switch self {
        case .accountSelectionRequired:
            return "Select an account first."
        case let .accountNotFound(identityKey):
            return "The saved account (\(identityKey)) is no longer available."
        case let .missingStoredSnapshot(accountName):
            return "Codex Switcher no longer has a saved auth snapshot for \(accountName)."
        case let .invalidStoredSnapshot(accountName):
            return "The saved auth snapshot for \(accountName) is no longer valid."
        case .missingBookmark:
            return "Choose the Codex folder before switching accounts."
        case let .unsupportedAuthState(authState):
            switch authState {
            case .unlinked:
                return "Choose the Codex folder before switching accounts."
            case .loggedOut, .ready:
                return "Codex Switcher couldn't confirm the linked Codex folder."
            case .locationUnavailable:
                return "The linked Codex folder is no longer available."
            case .accessDenied:
                return "Codex Switcher no longer has permission to access the linked Codex folder."
            case .corruptAuthFile:
                return "The linked auth.json is invalid."
            case .unsupportedCredentialStore:
                return "The linked Codex folder uses an unsupported credential store."
            }
        case let .accessDenied(folderURL):
            return "Codex Switcher no longer has permission to access \(folderURL.path)."
        case let .linkedFolderUnavailable(folderURL):
            return "The linked Codex folder is no longer available: \(folderURL.path)."
        case let .unreadable(fileURL, message):
            return "Codex Switcher couldn't read \(fileURL.path). \(message)"
        case let .unwritable(fileURL, message):
            return "Codex Switcher couldn't write \(fileURL.path). \(message)"
        case let .verificationFailed(fileURL):
            return "Codex Switcher wrote \(fileURL.path), but the verification readback did not match the saved account."
        }
    }
}

struct CodexSharedAccountSwitchService: Sendable {
    private let stateStore: CodexSharedStateStore
    private let bookmarkStore: CodexSharedBookmarkStore
    private let lock: CodexSharedProcessLock

    nonisolated init(
        stateStore: CodexSharedStateStore = CodexSharedStateStore(),
        bookmarkStore: CodexSharedBookmarkStore = CodexSharedBookmarkStore(),
        lock: CodexSharedProcessLock = CodexSharedProcessLock()
    ) {
        self.stateStore = stateStore
        self.bookmarkStore = bookmarkStore
        self.lock = lock
    }

    /// Performs the actual auth.json switch from a widget/control/intent
    /// process. The service never touches SwiftData directly; it only consumes
    /// the app-prepared App Group snapshot and the shared security-scoped
    /// bookmark so extensions stay lightweight and deterministic.
    nonisolated func switchToAccount(identityKey: String) throws -> SharedCodexAccountRecord {
        do {
            let switchedAccount = try lock.withExclusiveAccess {
                try performSwitch(identityKey: identityKey)
            }
            CodexSharedSurfaceReloader.reloadAll()
            CodexSharedSwitchFeedback.postSwitchSignal(
                identityKey: switchedAccount.id,
                accountName: switchedAccount.name
            )
            return switchedAccount
        } catch let error as CodexSharedSwitchError {
            try? persistFailureState(for: error)
            CodexSharedSurfaceReloader.reloadAll()
            throw error
        }
    }

    private nonisolated func performSwitch(identityKey: String) throws -> SharedCodexAccountRecord {
        var state = try stateStore.load()

        guard state.authState.canAttemptSwitch else {
            throw CodexSharedSwitchError.unsupportedAuthState(state.authState)
        }

        guard let account = state.account(withIdentityKey: identityKey) else {
            throw CodexSharedSwitchError.accountNotFound(identityKey)
        }

        guard let authFileContents = account.authFileContents, !authFileContents.isEmpty else {
            throw CodexSharedSwitchError.missingStoredSnapshot(account.name)
        }

        let storedSnapshot = try parseStoredSnapshot(contents: authFileContents, accountName: account.name)
        guard storedSnapshot.identityKey == identityKey else {
            throw CodexSharedSwitchError.invalidStoredSnapshot(account.name)
        }

        let folderURL = try resolveLinkedFolderURL()
        try withAuthorizedFolder(folderURL) { authorizedFolderURL in
            let authFileURL = authorizedFolderURL.appending(path: "auth.json", directoryHint: .notDirectory)
            try coordinatedWrite(authFileContents, to: authFileURL)

            let verifiedContents = try coordinatedRead(of: authFileURL)
            let verifiedSnapshot = try parseStoredSnapshot(contents: verifiedContents, accountName: account.name)
            guard verifiedSnapshot.identityKey == identityKey else {
                throw CodexSharedSwitchError.verificationFailed(authFileURL)
            }

            try? FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: Int16(0o600))],
                ofItemAtPath: authFileURL.path
            )
        }

        state.authState = .ready
        state.linkedFolderPath = folderURL.path
        state.currentAccountID = identityKey
        state.updatedAt = .now
        state.accounts = state.accounts.map { existingAccount in
            var updatedAccount = existingAccount
            if updatedAccount.id == identityKey {
                updatedAccount.lastLoginAt = .now
            }

            return updatedAccount
        }
        try stateStore.save(state)

        return account
    }

    private nonisolated func parseStoredSnapshot(contents: String, accountName: String) throws -> SharedCodexAuthSnapshot {
        do {
            return try SharedCodexAuthFile.parse(contents: contents)
        } catch {
            throw CodexSharedSwitchError.invalidStoredSnapshot(accountName)
        }
    }

    private nonisolated func resolveLinkedFolderURL() throws -> URL {
        guard let bookmarkData = try bookmarkStore.load() else {
            throw CodexSharedSwitchError.missingBookmark
        }

        var isStale = false
        let folderURL = try URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope, .withoutImplicitStartAccessing, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ).standardizedFileURL

        if isStale {
            let refreshedBookmark = try folderURL.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            try? bookmarkStore.save(refreshedBookmark)
        }

        return folderURL
    }

    private nonisolated func withAuthorizedFolder<T>(_ folderURL: URL, _ body: (URL) throws -> T) throws -> T {
        let started = folderURL.startAccessingSecurityScopedResource()
        guard started else {
            throw CodexSharedSwitchError.accessDenied(folderURL)
        }

        defer { folderURL.stopAccessingSecurityScopedResource() }
        guard directoryExists(at: folderURL) else {
            throw CodexSharedSwitchError.linkedFolderUnavailable(folderURL)
        }

        return try body(folderURL)
    }

    private nonisolated func coordinatedRead(of authFileURL: URL) throws -> String {
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
            throw CodexSharedSwitchError.unreadable(authFileURL, message: coordinationError.localizedDescription)
        }

        if let readError {
            throw CodexSharedSwitchError.unreadable(authFileURL, message: readError.localizedDescription)
        }

        guard let readContents else {
            throw CodexSharedSwitchError.unreadable(
                authFileURL,
                message: "The file coordinator returned no contents."
            )
        }

        return readContents
    }

    private nonisolated func coordinatedWrite(_ contents: String, to authFileURL: URL) throws {
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
            throw CodexSharedSwitchError.unwritable(authFileURL, message: coordinationError.localizedDescription)
        }

        if let writeError {
            throw CodexSharedSwitchError.unwritable(authFileURL, message: writeError.localizedDescription)
        }
    }

    private nonisolated func directoryExists(at folderURL: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDirectory) else {
            return false
        }

        return isDirectory.boolValue
    }

    private nonisolated func persistFailureState(for error: CodexSharedSwitchError) throws {
        var state = try stateStore.load()

        switch error {
        case .missingBookmark:
            state.authState = .unlinked
            state.linkedFolderPath = nil
            state.currentAccountID = nil
        case let .accessDenied(folderURL):
            state.authState = .accessDenied
            state.linkedFolderPath = folderURL.path
            state.currentAccountID = nil
        case let .linkedFolderUnavailable(folderURL):
            state.authState = .locationUnavailable
            state.linkedFolderPath = folderURL.path
            state.currentAccountID = nil
        case let .unsupportedAuthState(authState):
            state.authState = authState
        case .accountSelectionRequired,
             .accountNotFound,
             .missingStoredSnapshot,
             .invalidStoredSnapshot,
             .unreadable,
             .unwritable,
             .verificationFailed:
            return
        }

        state.updatedAt = .now
        try stateStore.save(state)
    }
}
