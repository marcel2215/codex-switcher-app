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
    case noBestAccountAvailable
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
        case .noBestAccountAvailable:
            return "No saved account currently has both 5h and 7d rate limits available for ranking."
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

enum CodexSharedAccountSwitchOutcome: Sendable, Equatable {
    case switched(SharedCodexAccountRecord)
    case alreadyCurrent(SharedCodexAccountRecord)

    nonisolated var account: SharedCodexAccountRecord {
        switch self {
        case let .switched(account), let .alreadyCurrent(account):
            account
        }
    }

    nonisolated var didChangeAccount: Bool {
        switch self {
        case .switched:
            true
        case .alreadyCurrent:
            false
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
    nonisolated func switchToAccount(identityKey: String) throws -> CodexSharedAccountSwitchOutcome {
        do {
            let outcome = try lock.withExclusiveAccess {
                try performSwitch(identityKey: identityKey)
            }
            return finalizeSwitchOutcome(outcome)
        } catch let error as CodexSharedSwitchError {
            try? persistFailureState(for: error)
            CodexSharedSurfaceReloader.reloadAll()
            throw error
        }
    }

    nonisolated func switchToBestAccount() throws -> CodexSharedAccountSwitchOutcome {
        do {
            let outcome = try lock.withExclusiveAccess {
                let state = try stateStore.load()
                guard let bestAccount = Self.bestRateLimitCandidate(in: state.accounts) else {
                    throw CodexSharedSwitchError.noBestAccountAvailable
                }

                return try performSwitch(identityKey: bestAccount.id, initialState: state)
            }
            return finalizeSwitchOutcome(outcome)
        } catch let error as CodexSharedSwitchError {
            try? persistFailureState(for: error)
            CodexSharedSurfaceReloader.reloadAll()
            throw error
        }
    }

    private nonisolated func finalizeSwitchOutcome(
        _ outcome: CodexSharedAccountSwitchOutcome
    ) -> CodexSharedAccountSwitchOutcome {
        CodexSharedSurfaceReloader.reloadAll()

        if outcome.didChangeAccount {
            CodexSharedSwitchFeedback.postSwitchSignal(
                identityKey: outcome.account.id,
                accountName: outcome.account.name
            )
        }

        return outcome
    }

    private nonisolated func performSwitch(
        identityKey: String,
        initialState: SharedCodexState? = nil
    ) throws -> CodexSharedAccountSwitchOutcome {
        var state = try initialState ?? stateStore.load()

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
        var didWriteAuthFile = false
        try withAuthorizedFolder(folderURL) { authorizedFolderURL in
            let authFileURL = authorizedFolderURL.appending(path: "auth.json", directoryHint: .notDirectory)

            if FileManager.default.fileExists(atPath: authFileURL.path) {
                let existingContents = try coordinatedRead(of: authFileURL)
                if existingContents == authFileContents {
                    return
                }
            }

            try coordinatedWrite(authFileContents, to: authFileURL)
            didWriteAuthFile = true

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
            if didWriteAuthFile, updatedAccount.id == identityKey {
                updatedAccount.lastLoginAt = .now
            }

            return updatedAccount
        }
        try stateStore.save(state)

        return didWriteAuthFile ? .switched(account) : .alreadyCurrent(account)
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
        let folderURL: URL
        do {
            folderURL = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope, .withoutImplicitStartAccessing, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ).standardizedFileURL
        } catch {
            throw normalizedBookmarkResolutionError(from: error)
        }

        if isStale {
            // A stale bookmark still resolved to a usable URL for this run. Do
            // not fail the switch just because refreshing persistence failed.
            do {
                let refreshedBookmark = try folderURL.bookmarkData(
                    options: [.withSecurityScope],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                try? bookmarkStore.save(refreshedBookmark)
            } catch {
            }
        }

        return folderURL
    }

    /// Shortcuts surfaces raw bookmark-resolution failures as a generic
    /// "The file couldn’t be opened" Cocoa error. Normalize those failures so
    /// App Intents can ask the user to relink or reopen the Codex folder.
    private nonisolated func normalizedBookmarkResolutionError(from error: Error) -> CodexSharedSwitchError {
        let nsError = error as NSError
        let linkedFolderURLHint = linkedFolderURLHint()

        guard nsError.domain == NSCocoaErrorDomain else {
            return .missingBookmark
        }

        switch nsError.code {
        case NSFileReadNoPermissionError, NSFileWriteNoPermissionError:
            if let linkedFolderURLHint {
                return .accessDenied(linkedFolderURLHint)
            }

        case NSFileNoSuchFileError, NSFileReadNoSuchFileError:
            if let linkedFolderURLHint {
                return .linkedFolderUnavailable(linkedFolderURLHint)
            }

        default:
            break
        }

        return .missingBookmark
    }

    private nonisolated func linkedFolderURLHint() -> URL? {
        guard let linkedFolderPath = try? stateStore.load().linkedFolderPath else {
            return nil
        }

        let trimmedLinkedFolderPath = linkedFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLinkedFolderPath.isEmpty else {
            return nil
        }

        return URL(filePath: trimmedLinkedFolderPath)
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
             .noBestAccountAvailable,
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

    nonisolated static func bestRateLimitCandidate(
        in accounts: [SharedCodexAccountRecord]
    ) -> SharedCodexAccountRecord? {
        accounts
            .sorted { lhs, rhs in
                if areEquivalentForRateLimitSort(lhs, rhs) {
                    return lhs.sortOrder < rhs.sortOrder
                }

                return rateLimitSortComesBefore(lhs, rhs)
            }
            .first(where: { rateLimitSortMetrics(for: $0).isComplete })
    }

    private nonisolated static func rateLimitSortComesBefore(
        _ lhs: SharedCodexAccountRecord,
        _ rhs: SharedCodexAccountRecord
    ) -> Bool {
        let lhsMetrics = rateLimitSortMetrics(for: lhs)
        let rhsMetrics = rateLimitSortMetrics(for: rhs)

        if lhsMetrics.isComplete != rhsMetrics.isComplete {
            return lhsMetrics.isComplete
        }

        if lhsMetrics.primary != rhsMetrics.primary {
            return lhsMetrics.primary > rhsMetrics.primary
        }

        if lhsMetrics.secondary != rhsMetrics.secondary {
            return lhsMetrics.secondary > rhsMetrics.secondary
        }

        return lhs.sortOrder < rhs.sortOrder
    }

    private nonisolated static func areEquivalentForRateLimitSort(
        _ lhs: SharedCodexAccountRecord,
        _ rhs: SharedCodexAccountRecord
    ) -> Bool {
        let lhsMetrics = rateLimitSortMetrics(for: lhs)
        let rhsMetrics = rateLimitSortMetrics(for: rhs)
        return lhsMetrics.isComplete == rhsMetrics.isComplete
            && lhsMetrics.primary == rhsMetrics.primary
            && lhsMetrics.secondary == rhsMetrics.secondary
    }

    private nonisolated static func rateLimitSortMetrics(
        for account: SharedCodexAccountRecord
    ) -> (isComplete: Bool, primary: Int, secondary: Int) {
        let normalizedValues = normalizedRateLimitSortValues(for: account)
        return (
            normalizedValues.isComplete,
            normalizedValues.values.min() ?? 0,
            normalizedValues.values.max() ?? 0
        )
    }

    private nonisolated static func normalizedRateLimitSortValues(
        for account: SharedCodexAccountRecord
    ) -> (isComplete: Bool, values: [Int]) {
        guard let fiveHourRemainingPercent = account.fiveHourLimitUsedPercent,
              let sevenDayRemainingPercent = account.sevenDayLimitUsedPercent
        else {
            return (false, [0, 0])
        }

        return (
            true,
            [fiveHourRemainingPercent, sevenDayRemainingPercent]
                .map { min(max($0, 0), 100) }
        )
    }
}
