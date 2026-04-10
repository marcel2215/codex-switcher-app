//
//  CodexSharedAppIntents.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-08.
//

import AppIntents
import SwiftUI
import WidgetKit

struct CodexAccountEntity: AppEntity, Hashable, Sendable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Codex Account")
    static let defaultQuery = CodexAccountEntityQuery()

    let id: String

    @Property(title: "Name")
    var name: String

    @Property(title: "Email")
    var emailHint: String?

    var iconSystemName: String
    var isCurrent: Bool

    nonisolated var displayRepresentation: DisplayRepresentation {
        if let emailHint, !emailHint.isEmpty {
            return DisplayRepresentation(title: "\(name)", subtitle: "\(emailHint)")
        }

        if isCurrent {
            return DisplayRepresentation(title: "\(name)", subtitle: "Current account")
        }

        return DisplayRepresentation(title: "\(name)")
    }

    nonisolated init(record: SharedCodexAccountRecord, currentAccountID: String?) {
        self.id = record.id
        self.iconSystemName = record.iconSystemName
        self.isCurrent = record.id == currentAccountID
        self.name = record.name
        self.emailHint = record.emailHint
    }

    static func == (lhs: CodexAccountEntity, rhs: CodexAccountEntity) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum CodexSharedIntentLookupError: LocalizedError {
    case noSavedAccounts
    case noCurrentAccount
    case noSelectedAccount
    case emptySearchQuery
    case noMatchingAccount(String)
    case noMatchingAccounts(String)

    nonisolated var errorDescription: String? {
        switch self {
        case .noSavedAccounts:
            return "Codex Switcher doesn't have any saved accounts yet."
        case .noCurrentAccount:
            return "Codex Switcher couldn't determine the current account."
        case .noSelectedAccount:
            return "No single account is currently selected in Codex Switcher."
        case .emptySearchQuery:
            return "Enter an account name, email, or identifier to search."
        case let .noMatchingAccount(query):
            return "No saved account matched “\(query)”."
        case let .noMatchingAccounts(query):
            return "No saved accounts matched “\(query)”."
        }
    }
}

enum CodexSharedAccountIntentResolver {
    nonisolated static func selectedEntityResolution(
        in state: SharedCodexState
    ) throws -> (entity: CodexAccountEntity, usedCurrentFallback: Bool) {
        if let account = state.selectedAccount {
            return (
                CodexAccountEntity(record: account, currentAccountID: state.currentAccountID),
                false
            )
        }

        if let account = state.currentAccount {
            return (
                CodexAccountEntity(record: account, currentAccountID: state.currentAccountID),
                true
            )
        }

        throw CodexSharedIntentLookupError.noSelectedAccount
    }

    nonisolated static func loadState(
        store: CodexSharedStateStore = CodexSharedStateStore()
    ) throws -> SharedCodexState {
        try store.load()
    }

    nonisolated static func allEntities(in state: SharedCodexState) throws -> [CodexAccountEntity] {
        guard !state.accounts.isEmpty else {
            throw CodexSharedIntentLookupError.noSavedAccounts
        }

        return state.accounts.map {
            CodexAccountEntity(record: $0, currentAccountID: state.currentAccountID)
        }
    }

    nonisolated static func currentEntity(in state: SharedCodexState) throws -> CodexAccountEntity {
        guard let account = state.currentAccount else {
            throw CodexSharedIntentLookupError.noCurrentAccount
        }

        return CodexAccountEntity(record: account, currentAccountID: state.currentAccountID)
    }

    nonisolated static func selectedEntity(in state: SharedCodexState) throws -> CodexAccountEntity {
        try selectedEntityResolution(in: state).entity
    }

    nonisolated static func bestEntity(in state: SharedCodexState) throws -> CodexAccountEntity {
        guard let account = CodexSharedAccountSwitchService.bestRateLimitCandidate(in: state.accounts) else {
            throw CodexSharedSwitchError.noBestAccountAvailable
        }

        return CodexAccountEntity(record: account, currentAccountID: state.currentAccountID)
    }

    nonisolated static func preferredEntity(
        matching rawQuery: String,
        in state: SharedCodexState
    ) throws -> CodexAccountEntity {
        let matches = try matchingEntities(matching: rawQuery, in: state)
        guard let firstMatch = matches.first else {
            throw CodexSharedIntentLookupError.noMatchingAccount(rawQuery)
        }

        return firstMatch
    }

    nonisolated static func matchingEntities(
        matching rawQuery: String,
        in state: SharedCodexState
    ) throws -> [CodexAccountEntity] {
        let query = normalized(rawQuery)
        guard !query.isEmpty else {
            throw CodexSharedIntentLookupError.emptySearchQuery
        }

        let matches = state.accounts.enumerated()
            .compactMap { index, account -> (rank: Int, index: Int, entity: CodexAccountEntity)? in
                guard let rank = matchRank(for: account, query: query) else {
                    return nil
                }

                return (
                    rank: rank,
                    index: index,
                    entity: CodexAccountEntity(record: account, currentAccountID: state.currentAccountID)
                )
            }
            .sorted { lhs, rhs in
                if lhs.rank != rhs.rank {
                    return lhs.rank < rhs.rank
                }

                return lhs.index < rhs.index
            }
            .map(\.entity)

        guard !matches.isEmpty else {
            throw CodexSharedIntentLookupError.noMatchingAccounts(rawQuery)
        }

        return matches
    }

    private nonisolated static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private nonisolated static func matchRank(
        for account: SharedCodexAccountRecord,
        query: String
    ) -> Int? {
        let searchableValues = [
            account.name,
            account.emailHint,
            account.accountIdentifier,
            account.id,
        ]
        .compactMap { $0 }
        .map(normalized(_:))
        .filter { !$0.isEmpty }

        guard !searchableValues.isEmpty else {
            return nil
        }

        if searchableValues.contains(query) {
            return 0
        }

        if searchableValues.contains(where: { $0.hasPrefix(query) }) {
            return 1
        }

        if searchableValues.contains(where: { $0.contains(query) }) {
            return 2
        }

        return nil
    }
}

struct CodexAccountEntityQuery: EntityStringQuery {
    private let store: CodexSharedStateStore

    nonisolated init() {
        self.store = CodexSharedStateStore()
    }

    nonisolated init(store: CodexSharedStateStore) {
        self.store = store
    }

    nonisolated func entities(for identifiers: [String]) async throws -> [CodexAccountEntity] {
        let state = try CodexSharedAccountIntentResolver.loadState(store: store)
        let entitiesByIdentifier = Dictionary(
            uniqueKeysWithValues: state.accounts.map { ($0.id, CodexAccountEntity(record: $0, currentAccountID: state.currentAccountID)) }
        )

        return identifiers.compactMap { entitiesByIdentifier[$0] }
    }

    nonisolated func suggestedEntities() async throws -> [CodexAccountEntity] {
        let state = try CodexSharedAccountIntentResolver.loadState(store: store)

        do {
            return try CodexSharedAccountIntentResolver.allEntities(in: state)
        } catch CodexSharedIntentLookupError.noSavedAccounts {
            return []
        }
    }

    nonisolated func entities(matching string: String) async throws -> [CodexAccountEntity] {
        let state = try CodexSharedAccountIntentResolver.loadState(store: store)

        do {
            return try CodexSharedAccountIntentResolver.matchingEntities(matching: string, in: state)
        } catch let error as CodexSharedIntentLookupError {
            switch error {
            case .noSavedAccounts, .emptySearchQuery, .noMatchingAccounts:
                return []
            case .noCurrentAccount, .noSelectedAccount, .noMatchingAccount:
                throw error
            }
        }
    }
}

struct CodexSwitcherAppShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor {
        .blue
    }

    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenCodexSwitcherIntent(),
            phrases: [
                "Open \(.applicationName)",
                "Open Codex Switcher in \(.applicationName)",
            ],
            shortTitle: "Open App",
            systemImageName: "key.card.fill"
        )

        AppShortcut(
            intent: SwitchToBestAccountIntent(),
            phrases: [
                "Switch to the best account in \(.applicationName)",
                "Use the best Codex account in \(.applicationName)",
            ],
            shortTitle: "Best Account",
            systemImageName: "arrow.up.circle.fill"
        )

        AppShortcut(
            intent: GetCurrentAccountIntent(),
            phrases: [
                "Get the current account in \(.applicationName)",
                "What account is active in \(.applicationName)",
            ],
            shortTitle: "Current Account",
            systemImageName: "person.text.rectangle"
        )

        AppShortcut(
            intent: AddCurrentAccountIntent(),
            phrases: [
                "Add the current Codex account to \(.applicationName)",
                "Save the current Codex account in \(.applicationName)",
            ],
            shortTitle: "Add Account",
            systemImageName: "plus.circle.fill"
        )
    }
}

struct AddCurrentAccountIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Current Codex Account"
    static let description = IntentDescription("Opens Codex Switcher and saves the account currently logged into Codex.")
    static let openAppWhenRun = true

    nonisolated func perform() async throws -> some IntentResult & ProvidesDialog {
        try CodexSharedAppCommandQueue().enqueue(
            CodexSharedAppCommand(action: .captureCurrentAccount)
        )
        CodexSharedAppCommandSignal.postCommandQueuedSignal()

        return .result(
            dialog: IntentDialog("Opening Codex Switcher to save the current account.")
        )
    }
}

struct GetSelectedAccountIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Selected Codex Account"
    static let description = IntentDescription(
        "Returns the account currently selected in Codex Switcher, or the current account if no live list selection is active."
    )

    nonisolated func perform() async throws -> some IntentResult & ReturnsValue<CodexAccountEntity> & ProvidesDialog {
        let state = try CodexSharedAccountIntentResolver.loadState()
        let resolution = try CodexSharedAccountIntentResolver.selectedEntityResolution(in: state)

        return .result(
            value: resolution.entity,
            dialog: IntentDialog(
                resolution.usedCurrentFallback
                    ? "No live selection was available, so using the current account: \"\(resolution.entity.name)\"."
                    : "Selected account: \"\(resolution.entity.name)\"."
            )
        )
    }
}

struct GetCurrentAccountIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Current Codex Account"
    static let description = IntentDescription("Returns the account currently active in Codex.")

    nonisolated func perform() async throws -> some IntentResult & ReturnsValue<CodexAccountEntity> & ProvidesDialog {
        let state = try CodexSharedAccountIntentResolver.loadState()
        let account = try CodexSharedAccountIntentResolver.currentEntity(in: state)

        return .result(
            value: account,
            dialog: IntentDialog("Current account: \"\(account.name)\".")
        )
    }
}

struct GetAllAccountsIntent: AppIntent {
    static let title: LocalizedStringResource = "Get All Codex Accounts"
    static let description = IntentDescription("Returns all saved Codex accounts.")

    nonisolated func perform() async throws -> some IntentResult & ReturnsValue<[CodexAccountEntity]> & ProvidesDialog {
        let state = try CodexSharedAccountIntentResolver.loadState()
        let accounts = try CodexSharedAccountIntentResolver.allEntities(in: state)

        return .result(
            value: accounts,
            dialog: IntentDialog("Found \(accounts.count) saved Codex account(s).")
        )
    }
}

struct GetBestAccountIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Best Codex Account"
    static let description = IntentDescription("Returns the saved account with the most remaining rate-limit headroom.")

    nonisolated func perform() async throws -> some IntentResult & ReturnsValue<CodexAccountEntity> & ProvidesDialog {
        let state = try CodexSharedAccountIntentResolver.loadState()
        let account = try CodexSharedAccountIntentResolver.bestEntity(in: state)

        return .result(
            value: account,
            dialog: IntentDialog("Best account: \"\(account.name)\".")
        )
    }
}

struct FindAccountIntent: AppIntent {
    static let title: LocalizedStringResource = "Find Codex Account"
    static let description = IntentDescription("Finds the best single saved account match by name, email, or identifier.")

    @Parameter(title: "Search")
    var search: String

    static var parameterSummary: some ParameterSummary {
        Summary("Find account matching \(\.$search)")
    }

    nonisolated func perform() async throws -> some IntentResult & ReturnsValue<CodexAccountEntity> & ProvidesDialog {
        let state = try CodexSharedAccountIntentResolver.loadState()
        let account = try CodexSharedAccountIntentResolver.preferredEntity(matching: search, in: state)

        return .result(
            value: account,
            dialog: IntentDialog("Matched \"\(account.name)\".")
        )
    }
}

struct FindAccountsIntent: AppIntent {
    static let title: LocalizedStringResource = "Find Codex Accounts"
    static let description = IntentDescription("Finds all saved accounts matching a name, email, or identifier.")

    @Parameter(title: "Search")
    var search: String

    static var parameterSummary: some ParameterSummary {
        Summary("Find accounts matching \(\.$search)")
    }

    nonisolated func perform() async throws -> some IntentResult & ReturnsValue<[CodexAccountEntity]> & ProvidesDialog {
        let state = try CodexSharedAccountIntentResolver.loadState()
        let accounts = try CodexSharedAccountIntentResolver.matchingEntities(matching: search, in: state)

        return .result(
            value: accounts,
            dialog: IntentDialog("Found \(accounts.count) matching Codex account(s).")
        )
    }
}

struct RemoveAccountIntent: AppIntent {
    static let title: LocalizedStringResource = "Remove Codex Account"
    static let description = IntentDescription("Opens Codex Switcher and removes one saved account.")
    static let openAppWhenRun = true

    @Parameter(title: "Account")
    var account: CodexAccountEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Remove \(\.$account)")
    }

    nonisolated func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let account else {
            throw CodexSharedSwitchError.accountSelectionRequired
        }

        try CodexSharedAppCommandQueue().enqueue(
            CodexSharedAppCommand(
                action: .removeAccount,
                accountIdentityKey: account.id
            )
        )
        CodexSharedAppCommandSignal.postCommandQueuedSignal()

        return .result(
            dialog: IntentDialog("Opening Codex Switcher to remove \"\(account.name)\".")
        )
    }
}

struct SwitchAccountIntent: AppIntent, ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Switch Codex Account"
    static let description = IntentDescription("Switches Codex to one of your saved accounts.")

    @Parameter(title: "Account")
    var account: CodexAccountEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Switch to \(\.$account)")
    }

    nonisolated func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let account else {
            throw CodexSharedSwitchError.accountSelectionRequired
        }

        let outcome = try CodexSharedAccountSwitchService().switchToAccount(identityKey: account.id)

        if outcome.didChangeAccount {
            await CodexSharedSwitchFeedback.postLocalSwitchNotificationIfAuthorized(
                accountName: outcome.account.name
            )

            return .result(
                dialog: IntentDialog("Now using \"\(outcome.account.name)\".")
            )
        }

        return .result(
            dialog: IntentDialog("Already using \"\(outcome.account.name)\".")
        )
    }
}

struct SwitchToBestAccountIntent: AppIntent {
    static let title: LocalizedStringResource = "Switch to Best Codex Account"
    static let description = IntentDescription("Switches to the saved account with the highest remaining 5h and 7d rate-limit headroom.")

    nonisolated func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = try CodexSharedAccountSwitchService().switchToBestAccount()

        if outcome.didChangeAccount {
            await CodexSharedSwitchFeedback.postLocalSwitchNotificationIfAuthorized(
                accountName: outcome.account.name
            )

            return .result(
                dialog: IntentDialog("Now using \"\(outcome.account.name)\", your best available account.")
            )
        }

        return .result(
            dialog: IntentDialog("Already using \"\(outcome.account.name)\", your best available account.")
        )
    }
}

struct OpenCodexSwitcherIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Codex Switcher"
    static let description = IntentDescription("Opens Codex Switcher.")
    static let openAppWhenRun = true

    nonisolated func perform() async throws -> some IntentResult {
        .result()
    }
}

struct QuitCodexSwitcherIntent: AppIntent {
    static let title: LocalizedStringResource = "Quit Codex Switcher"
    static let description = IntentDescription("Quits Codex Switcher if it is currently running.")

    nonisolated func perform() async throws -> some IntentResult & ProvidesDialog {
        guard CodexSharedAppCommandSignal.isMainApplicationRunning else {
            return .result(
                dialog: IntentDialog("Codex Switcher is not currently running.")
            )
        }

        try CodexSharedAppCommandQueue().enqueue(
            CodexSharedAppCommand(action: .quitApplication)
        )
        CodexSharedAppCommandSignal.postCommandQueuedSignal()

        return .result(
            dialog: IntentDialog("Quitting Codex Switcher.")
        )
    }
}
