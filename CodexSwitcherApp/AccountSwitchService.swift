//
//  AccountSwitchService.swift
//  Codex Switcher
//
//  Created by Marcel Kwiatkowski on 2026-04-08.
//

import Foundation

#if canImport(Darwin)
import Darwin
#endif

enum CodexSharedSwitchError: LocalizedError {
    case accountSelectionRequired
    case accountNotFound(String)
    case accountUnavailable(String)
    case noBestAccountAvailable
    case missingStoredSnapshot(String)
    case invalidStoredSnapshot(String)
    case missingBookmark
    case bookmarkRefreshRequired
    case unsupportedAuthState(SharedCodexAuthState)
    case unsupportedCredentialStore(URL, mode: CodexCredentialStoreHint)
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
        case let .accountUnavailable(accountName):
            return "The saved account \(accountName) is no longer available. Open Codex Switcher to remove it or capture a fresh login."
        case .noBestAccountAvailable:
            return "No saved account currently has both 5h and 7d rate limits available for ranking."
        case let .missingStoredSnapshot(accountName):
            return "Codex Switcher no longer has a saved auth snapshot for \(accountName)."
        case let .invalidStoredSnapshot(accountName):
            return "The saved auth snapshot for \(accountName) is no longer valid."
        case .missingBookmark:
            return "Choose the Codex folder before switching accounts."
        case .bookmarkRefreshRequired:
            return "Open Codex Switcher once to refresh access to the linked Codex folder."
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
        case let .unsupportedCredentialStore(folderURL, mode):
            return "The linked Codex folder at \(folderURL.path) is configured for \(mode.displayName) credential storage. Codex Switcher only supports file-backed auth.json switching."
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
    private let legacyBookmarkStore: CodexSharedBookmarkStore
    private let snapshotStore: AccountSnapshotStoring
    private let lock: CodexSharedProcessLock

    nonisolated init(
        stateStore: CodexSharedStateStore = CodexSharedStateStore(),
        bookmarkStore: CodexSharedBookmarkStore = CodexSharedBookmarkStore(),
        legacyBookmarkStore: CodexSharedBookmarkStore = CodexSharedBookmarkStore(
            filename: CodexSharedAppGroup.legacyBookmarkFilename
        ),
        snapshotStore: AccountSnapshotStoring? = nil,
        lock: CodexSharedProcessLock = CodexSharedProcessLock()
    ) {
        self.stateStore = stateStore
        self.bookmarkStore = bookmarkStore
        self.legacyBookmarkStore = legacyBookmarkStore
        self.snapshotStore = snapshotStore ?? SharedKeychainSnapshotStore()
        self.lock = lock
    }

    /// Performs the actual auth.json switch from a widget/control/intent
    /// process. The service never touches SwiftData directly; it only consumes
    /// the app-prepared App Group snapshot and the shared security-scoped
    /// bookmark so extensions stay lightweight and deterministic.
    nonisolated func switchToAccount(identityKey: String) async throws -> CodexSharedAccountSwitchOutcome {
        do {
            let outcome = try await lock.withExclusiveAccess {
                try await performSwitch(identityKey: identityKey)
            }
            return finalizeSwitchOutcome(outcome)
        } catch let error as CodexSharedSwitchError {
            try? persistFailureState(for: error)
            CodexSharedSurfaceReloader.reloadAll()
            throw error
        }
    }

    nonisolated func switchToBestAccount() async throws -> CodexSharedAccountSwitchOutcome {
        do {
            let outcome = try await lock.withExclusiveAccess {
                let state = try stateStore.load()
                guard let bestAccount = Self.bestRateLimitCandidate(in: state.accounts) else {
                    throw CodexSharedSwitchError.noBestAccountAvailable
                }

                return try await performSwitch(identityKey: bestAccount.id, initialState: state)
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
    ) async throws -> CodexSharedAccountSwitchOutcome {
        var state = try initialState ?? stateStore.load()

        guard state.authState.canAttemptSwitch else {
            throw CodexSharedSwitchError.unsupportedAuthState(state.authState)
        }

        guard let account = state.account(withIdentityKey: identityKey) else {
            throw CodexSharedSwitchError.accountNotFound(identityKey)
        }
        guard !account.isUnavailable else {
            throw CodexSharedSwitchError.accountUnavailable(account.name)
        }
        var outcomeAccount = account
        let loginAt = Date()

        let loadedAuthFileContents: String
        do {
            loadedAuthFileContents = try await snapshotStore.loadSnapshot(forIdentityKey: identityKey)
        } catch AccountSnapshotStoreError.missingSnapshot {
            throw CodexSharedSwitchError.missingStoredSnapshot(account.name)
        }
        let authFileContents: String
        do {
            authFileContents = try CodexAuthSnapshotNormalizer
                .normalizedForCodexRuntime(loadedAuthFileContents)
        } catch {
            throw CodexSharedSwitchError.invalidStoredSnapshot(account.name)
        }
        if authFileContents != loadedAuthFileContents {
            try await snapshotStore.saveSnapshot(authFileContents, forIdentityKey: identityKey)
        }

        let storedSnapshot = try parseStoredSnapshot(contents: authFileContents, accountName: account.name)
        guard storedSnapshot.identityKey == identityKey else {
            throw CodexSharedSwitchError.invalidStoredSnapshot(account.name)
        }

        let folderURL = try resolveLinkedFolderURL()
        var didWriteAuthFile = false
        try await withAuthorizedFolder(folderURL) { authorizedFolderURL in
            let credentialStoreHint = CodexCredentialStoreHint.detect(in: authorizedFolderURL)
            guard credentialStoreHint.isSupportedForFileSwitching else {
                throw CodexSharedSwitchError.unsupportedCredentialStore(
                    authorizedFolderURL,
                    mode: credentialStoreHint
                )
            }

            let authFileURL = authorizedFolderURL.appending(path: "auth.json", directoryHint: .notDirectory)

            if FileManager.default.fileExists(atPath: authFileURL.path) {
                let existingContents = try coordinatedRead(of: authFileURL)
                if existingContents == authFileContents {
                    return
                }

                if let existingSnapshot = try? SharedCodexAuthFile.parse(contents: existingContents) {
                    try await preserveExistingSnapshotIfKnown(
                        contents: existingContents,
                        snapshot: existingSnapshot,
                        knownAccounts: state.accounts,
                        replacingIdentityKey: identityKey
                    )
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
        state.updatedAt = loginAt
        state.accounts = state.accounts.map { existingAccount in
            var updatedAccount = existingAccount
            if updatedAccount.id == identityKey {
                Self.applyLastLogin(loginAt, to: &updatedAccount)
                outcomeAccount = updatedAccount
            }

            return updatedAccount
        }
        try stateStore.save(state)

        return didWriteAuthFile ? .switched(outcomeAccount) : .alreadyCurrent(outcomeAccount)
    }

    private nonisolated static func applyLastLogin(
        _ lastLoginAt: Date,
        to account: inout SharedCodexAccountRecord
    ) {
        if let existingLastLoginAt = account.lastLoginAt,
           existingLastLoginAt >= lastLoginAt {
            return
        }

        account.lastLoginAt = lastLoginAt
    }

    private nonisolated func preserveExistingSnapshotIfKnown(
        contents: String,
        snapshot: SharedCodexAuthSnapshot,
        knownAccounts: [SharedCodexAccountRecord],
        replacingIdentityKey: String
    ) async throws {
        guard
            snapshot.identityKey != replacingIdentityKey,
            knownAccounts.contains(where: { $0.id == snapshot.identityKey })
        else {
            return
        }

        try await snapshotStore.saveSnapshot(contents, forIdentityKey: snapshot.identityKey)
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
            if (try? legacyBookmarkStore.load()) != nil {
                throw CodexSharedSwitchError.bookmarkRefreshRequired
            }
            throw CodexSharedSwitchError.missingBookmark
        }

        var isStale = false
        let folderURL: URL
        do {
            folderURL = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withoutImplicitStartAccessing, .withoutUI],
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
                    options: [],
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

    private nonisolated func withAuthorizedFolder<T>(
        _ folderURL: URL,
        _ body: (URL) async throws -> T
    ) async throws -> T {
        let started = folderURL.startAccessingSecurityScopedResource()
        guard started else {
            throw CodexSharedSwitchError.accessDenied(folderURL)
        }

        defer { folderURL.stopAccessingSecurityScopedResource() }
        guard directoryExists(at: folderURL) else {
            throw CodexSharedSwitchError.linkedFolderUnavailable(folderURL)
        }

        return try await body(folderURL)
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

        NSFileCoordinator().coordinate(writingItemAt: authFileURL, options: [], error: &coordinationError) { url in
            do {
                try CodexAuthFileReplacement.replaceContents(contents, at: url)
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
        case .bookmarkRefreshRequired:
            return
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
        case let .unsupportedCredentialStore(folderURL, _):
            state.authState = .unsupportedCredentialStore
            state.linkedFolderPath = folderURL.path
            state.currentAccountID = nil
        case .accountSelectionRequired,
             .accountNotFound,
             .accountUnavailable,
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
            .filter { $0.hasLocalSnapshot && !$0.isUnavailable }
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
