//
//  CodexSharedAppIntents.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-08.
//

import AppIntents
import CoreSpotlight
import SwiftUI
import WidgetKit

private extension Optional where Wrapped == String {
    nonisolated var nilIfBlank: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        return value
    }
}

private extension String {
    nonisolated var localizedStringResource: LocalizedStringResource {
        LocalizedStringResource(stringLiteral: self)
    }
}

struct CodexAccountEntity: AppEntity, IndexedEntity, Hashable, Sendable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Codex Account")
    static let defaultQuery = CodexAccountEntityQuery()

    let id: String

    @Property(title: "Name")
    var name: String

    @Property(title: "Email")
    var emailHint: String?

    @Property(title: "Identifier")
    var accountIdentifier: String?

    @Property(title: "Current")
    var isCurrent: Bool

    @Property(title: "Last Login")
    var lastLoginAt: Date?

    @Property(title: "5h Limit Used")
    var fiveHourLimitUsedPercent: Int?

    @Property(title: "7d Limit Used")
    var sevenDayLimitUsedPercent: Int?

    var iconSystemName: String
    var sortOrder: Double

    nonisolated var displayRepresentation: DisplayRepresentation {
        let subtitleParts = [
            isCurrent ? "Current" : nil,
            emailHint.nilIfBlank,
            accountIdentifier.nilIfBlank,
        ]
        .compactMap { $0 }

        let subtitle = subtitleParts.joined(separator: " • ")
        return DisplayRepresentation(
            title: name.localizedStringResource,
            subtitle: subtitle.isEmpty ? nil : subtitle.localizedStringResource,
            image: .init(systemName: iconSystemName)
        )
    }

    nonisolated var attributeSet: CSSearchableItemAttributeSet {
        let attributeSet = defaultAttributeSet
        attributeSet.displayName = name
        attributeSet.contentDescription = [
            isCurrent ? "Current account" : nil,
            emailHint.nilIfBlank,
            accountIdentifier.nilIfBlank,
        ]
        .compactMap { $0 }
        .joined(separator: " • ")
        attributeSet.keywords = [
            name,
            emailHint.nilIfBlank,
            accountIdentifier.nilIfBlank,
            isCurrent ? "Current" : nil,
            "Codex",
            "Account",
        ]
        .compactMap { $0 }

        if let lastLoginAt {
            attributeSet.lastUsedDate = lastLoginAt
        }

        return attributeSet
    }

    nonisolated init(record: SharedCodexAccountRecord, currentAccountID: String?) {
        self.id = record.id
        self.iconSystemName = record.iconSystemName
        self.sortOrder = record.sortOrder
        self.name = record.name
        self.emailHint = record.emailHint
        self.accountIdentifier = record.accountIdentifier
        self.isCurrent = record.id == currentAccountID
        self.lastLoginAt = record.lastLoginAt
        self.fiveHourLimitUsedPercent = record.fiveHourLimitUsedPercent
        self.sevenDayLimitUsedPercent = record.sevenDayLimitUsedPercent
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
            return "No live account selection is currently available in Codex Switcher."
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
    nonisolated static func loadState(
        store: CodexSharedStateStore = CodexSharedStateStore()
    ) throws -> SharedCodexState {
        try store.load()
    }

    nonisolated static func allEntities(in state: SharedCodexState) -> [CodexAccountEntity] {
        state.accounts.map {
            CodexAccountEntity(record: $0, currentAccountID: state.currentAccountID)
        }
    }

    nonisolated static func entity(
        withIdentityKey identityKey: String,
        in state: SharedCodexState
    ) -> CodexAccountEntity? {
        guard let account = state.account(withIdentityKey: identityKey) else {
            return nil
        }

        return CodexAccountEntity(record: account, currentAccountID: state.currentAccountID)
    }

    nonisolated static func currentEntity(in state: SharedCodexState) throws -> CodexAccountEntity {
        guard let account = state.currentAccount else {
            throw CodexSharedIntentLookupError.noCurrentAccount
        }

        return CodexAccountEntity(record: account, currentAccountID: state.currentAccountID)
    }

    nonisolated static func selectedEntity(in state: SharedCodexState) throws -> CodexAccountEntity {
        guard let account = state.selectedAccount else {
            throw CodexSharedIntentLookupError.noSelectedAccount
        }

        return CodexAccountEntity(record: account, currentAccountID: state.currentAccountID)
    }

    nonisolated static func selectedOrCurrentEntityResolution(
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

    nonisolated static func suggestedEntities(in state: SharedCodexState) -> [CodexAccountEntity] {
        allEntities(in: state).sorted(by: suggestionComparator)
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

                if lhs.index != rhs.index {
                    return lhs.index < rhs.index
                }

                return suggestionComparator(lhs: lhs.entity, rhs: rhs.entity)
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
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
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

    private nonisolated static func suggestionComparator(
        lhs: CodexAccountEntity,
        rhs: CodexAccountEntity
    ) -> Bool {
        if lhs.isCurrent != rhs.isCurrent {
            return lhs.isCurrent && !rhs.isCurrent
        }

        if lhs.lastLoginAt != rhs.lastLoginAt {
            return (lhs.lastLoginAt ?? .distantPast) > (rhs.lastLoginAt ?? .distantPast)
        }

        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }

        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}

enum CodexAccountComparator: Sendable, Equatable {
    case nameContains(String)
    case emailContains(String)
    case identifierContains(String)
    case isCurrent(Bool)
    case lastLoginAfter(Date)
    case lastLoginBefore(Date)
    case fiveHourLimitAtLeast(Int)
    case fiveHourLimitAtMost(Int)
    case sevenDayLimitAtLeast(Int)
    case sevenDayLimitAtMost(Int)
}

struct CodexAccountEntityQuery: EntityStringQuery, EntityPropertyQuery {
    typealias ComparatorMappingType = CodexAccountComparator

    private let store: CodexSharedStateStore

    nonisolated init() {
        self.store = CodexSharedStateStore()
    }

    nonisolated init(store: CodexSharedStateStore) {
        self.store = store
    }

    static var findIntentDescription: IntentDescription? {
        IntentDescription(
            "Finds saved Codex accounts by name, email, identifier, current status, last login, or rate-limit usage."
        )
    }

    nonisolated(unsafe) static let properties = QueryProperties {
        Property(\CodexAccountEntity.$name) {
            ContainsComparator { CodexAccountComparator.nameContains($0) }
        }
        Property(\CodexAccountEntity.$emailHint) {
            ContainsComparator { CodexAccountComparator.emailContains($0) }
        }
        Property(\CodexAccountEntity.$accountIdentifier) {
            ContainsComparator { CodexAccountComparator.identifierContains($0) }
        }
        Property(\CodexAccountEntity.$isCurrent) {
            EqualToComparator { CodexAccountComparator.isCurrent($0) }
        }
        Property(\CodexAccountEntity.$lastLoginAt) {
            GreaterThanComparator { CodexAccountComparator.lastLoginAfter($0) }
            LessThanComparator { CodexAccountComparator.lastLoginBefore($0) }
        }
        Property(\CodexAccountEntity.$fiveHourLimitUsedPercent) {
            GreaterThanOrEqualToComparator { CodexAccountComparator.fiveHourLimitAtLeast($0) }
            LessThanOrEqualToComparator { CodexAccountComparator.fiveHourLimitAtMost($0) }
        }
        Property(\CodexAccountEntity.$sevenDayLimitUsedPercent) {
            GreaterThanOrEqualToComparator { CodexAccountComparator.sevenDayLimitAtLeast($0) }
            LessThanOrEqualToComparator { CodexAccountComparator.sevenDayLimitAtMost($0) }
        }
    }

    nonisolated(unsafe) static let sortingOptions = SortingOptions {
        SortableBy(\CodexAccountEntity.$name)
        SortableBy(\CodexAccountEntity.$lastLoginAt)
        SortableBy(\CodexAccountEntity.$fiveHourLimitUsedPercent)
        SortableBy(\CodexAccountEntity.$sevenDayLimitUsedPercent)
    }

    nonisolated func entities(for identifiers: [String]) async throws -> [CodexAccountEntity] {
        let state = try CodexSharedAccountIntentResolver.loadState(store: store)
        let entitiesByIdentifier = Dictionary(
            uniqueKeysWithValues: CodexSharedAccountIntentResolver.allEntities(in: state).map { ($0.id, $0) }
        )

        return identifiers.compactMap { entitiesByIdentifier[$0] }
    }

    nonisolated func suggestedEntities() async throws -> [CodexAccountEntity] {
        let state = try CodexSharedAccountIntentResolver.loadState(store: store)
        return CodexSharedAccountIntentResolver.suggestedEntities(in: state)
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

    nonisolated func entities(
        matching comparators: [CodexAccountComparator],
        mode: ComparatorMode,
        sortedBy sorts: [Sort<CodexAccountEntity>],
        limit: Int?
    ) async throws -> [CodexAccountEntity] {
        let state = try CodexSharedAccountIntentResolver.loadState(store: store)
        var entities = CodexSharedAccountIntentResolver.allEntities(in: state)

        if !comparators.isEmpty {
            entities = entities.filter { entity in
                let comparatorMatches = comparators.map { comparator in
                    self.matches(comparator, entity: entity)
                }

                switch mode {
                case .and:
                    return comparatorMatches.allSatisfy(\.self)
                case .or:
                    return comparatorMatches.contains(true)
                }
            }
        }

        entities = sorted(entities, by: sorts)

        if let limit {
            return Array(entities.prefix(limit))
        }

        return entities
    }

    private nonisolated func matches(
        _ comparator: CodexAccountComparator,
        entity: CodexAccountEntity
    ) -> Bool {
        switch comparator {
        case let .nameContains(value):
            return entity.name.localizedCaseInsensitiveContains(value)
        case let .emailContains(value):
            return entity.emailHint?.localizedCaseInsensitiveContains(value) == true
        case let .identifierContains(value):
            return entity.accountIdentifier?.localizedCaseInsensitiveContains(value) == true
        case let .isCurrent(expected):
            return entity.isCurrent == expected
        case let .lastLoginAfter(date):
            return entity.lastLoginAt.map { $0 > date } == true
        case let .lastLoginBefore(date):
            return entity.lastLoginAt.map { $0 < date } == true
        case let .fiveHourLimitAtLeast(value):
            return entity.fiveHourLimitUsedPercent.map { $0 >= value } == true
        case let .fiveHourLimitAtMost(value):
            return entity.fiveHourLimitUsedPercent.map { $0 <= value } == true
        case let .sevenDayLimitAtLeast(value):
            return entity.sevenDayLimitUsedPercent.map { $0 >= value } == true
        case let .sevenDayLimitAtMost(value):
            return entity.sevenDayLimitUsedPercent.map { $0 <= value } == true
        }
    }

    private nonisolated func sorted(
        _ entities: [CodexAccountEntity],
        by sorts: [Sort<CodexAccountEntity>]
    ) -> [CodexAccountEntity] {
        guard !sorts.isEmpty else {
            return entities
        }

        return entities.sorted { lhs, rhs in
            for sort in sorts {
                let comparison = comparisonResult(lhs, rhs, for: sort)
                guard comparison != .orderedSame else {
                    continue
                }

                switch sort.order {
                case .ascending:
                    return comparison == .orderedAscending
                case .descending:
                    return comparison == .orderedDescending
                }
            }

            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private nonisolated func comparisonResult(
        _ lhs: CodexAccountEntity,
        _ rhs: CodexAccountEntity,
        for sort: Sort<CodexAccountEntity>
    ) -> ComparisonResult {
        switch sort.by {
        case \CodexAccountEntity.$name:
            return lhs.name.localizedStandardCompare(rhs.name)

        case \CodexAccountEntity.$lastLoginAt:
            return compareOptionalComparable(lhs.lastLoginAt, rhs.lastLoginAt)

        case \CodexAccountEntity.$fiveHourLimitUsedPercent:
            return compareOptionalComparable(lhs.fiveHourLimitUsedPercent, rhs.fiveHourLimitUsedPercent)

        case \CodexAccountEntity.$sevenDayLimitUsedPercent:
            return compareOptionalComparable(lhs.sevenDayLimitUsedPercent, rhs.sevenDayLimitUsedPercent)

        default:
            return .orderedSame
        }
    }

    private nonisolated func compareOptionalComparable<T: Comparable>(
        _ lhs: T?,
        _ rhs: T?
    ) -> ComparisonResult {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            if lhs < rhs {
                return .orderedAscending
            }

            if lhs > rhs {
                return .orderedDescending
            }

            return .orderedSame

        case (nil, nil):
            return .orderedSame

        case (nil, _?):
            return .orderedDescending

        case (_?, nil):
            return .orderedAscending
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
            intent: SwitchAccountIntent(),
            phrases: [
                "Switch Codex account in \(.applicationName)",
                "Use a saved Codex account in \(.applicationName)",
            ],
            shortTitle: "Switch Account",
            systemImageName: "arrow.left.arrow.right.circle"
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
    static let description = IntentDescription(
        "Opens Codex Switcher and saves the account currently logged into Codex."
    )
    static let supportedModes: IntentModes = .foreground

    nonisolated func perform() async throws -> some IntentResult & ReturnsValue<CodexAccountEntity> & ProvidesDialog {
        let command = CodexSharedAppCommand(
            action: .captureCurrentAccount,
            expectsResult: true
        )
        let result = try await awaitQueuedCommandResult(for: command)
        defer { try? CodexSharedAppCommandResultStore().remove(commandID: command.id) }

        guard result.status == .success else {
            throw CodexSharedIntentExecutionError.commandFailed(
                result.message ?? "Codex Switcher couldn't save the current account."
            )
        }

        let state = try CodexSharedAccountIntentResolver.loadState()
        let account: CodexAccountEntity
        if let identityKey = result.accountIdentityKey,
           let matchedAccount = CodexSharedAccountIntentResolver.entity(withIdentityKey: identityKey, in: state) {
            account = matchedAccount
        } else {
            account = try CodexSharedAccountIntentResolver.currentEntity(in: state)
        }
        let dialogMessage = result.message ?? "Saved \"\(account.name)\"."

        return .result(
            value: account,
            dialog: IntentDialog(stringLiteral: dialogMessage)
        )
    }
}

struct GetSelectedAccountIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Selected Codex Account"
    static let description = IntentDescription(
        "Returns the account currently selected in the visible Codex Switcher account list."
    )
    static let supportedModes: IntentModes = .background

    nonisolated func perform() async throws -> some IntentResult & ReturnsValue<CodexAccountEntity> & ProvidesDialog {
        let state = try CodexSharedAccountIntentResolver.loadState()
        let account = try CodexSharedAccountIntentResolver.selectedEntity(in: state)

        return .result(
            value: account,
            dialog: IntentDialog("Selected account: \"\(account.name)\".")
        )
    }
}

struct GetSelectedOrCurrentAccountIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Selected or Current Codex Account"
    static let description = IntentDescription(
        "Returns the selected account when a live list selection exists, otherwise the current account."
    )
    static let supportedModes: IntentModes = .background

    nonisolated func perform() async throws -> some IntentResult & ReturnsValue<CodexAccountEntity> & ProvidesDialog {
        let state = try CodexSharedAccountIntentResolver.loadState()
        let resolution = try CodexSharedAccountIntentResolver.selectedOrCurrentEntityResolution(in: state)

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
    static let supportedModes: IntentModes = .background

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
    static let supportedModes: IntentModes = .background

    nonisolated func perform() async throws -> some IntentResult & ReturnsValue<[CodexAccountEntity]> & ProvidesDialog {
        let state = try CodexSharedAccountIntentResolver.loadState()
        let accounts = CodexSharedAccountIntentResolver.allEntities(in: state)

        return .result(
            value: accounts,
            dialog: IntentDialog("Found \(accounts.count) saved Codex account(s).")
        )
    }
}

struct GetBestAccountIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Best Codex Account"
    static let description = IntentDescription(
        "Returns the saved account with the most remaining rate-limit headroom."
    )
    static let supportedModes: IntentModes = .background

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
    static let description = IntentDescription(
        "Finds the best single saved account match by name, email, or identifier."
    )
    static let supportedModes: IntentModes = .background

    @Parameter(
        title: "Search",
        requestValueDialog: IntentDialog("What Codex account should I search for?")
    )
    var search: String

    static var parameterSummary: some ParameterSummary {
        Summary("Find account matching \(\.$search)")
    }

    nonisolated func perform() async throws -> some IntentResult & ReturnsValue<CodexAccountEntity> & ProvidesDialog {
        let trimmedSearch = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSearch.isEmpty else {
            throw $search.needsValueError(
                IntentDialog("Provide an account name, email, or identifier to search for.")
            )
        }

        let state = try CodexSharedAccountIntentResolver.loadState()
        let account = try CodexSharedAccountIntentResolver.preferredEntity(matching: trimmedSearch, in: state)

        return .result(
            value: account,
            dialog: IntentDialog("Matched \"\(account.name)\".")
        )
    }
}

struct FindAccountsIntent: AppIntent {
    static let title: LocalizedStringResource = "Find Codex Accounts"
    static let description = IntentDescription(
        "Finds all saved accounts matching a name, email, or identifier."
    )
    static let supportedModes: IntentModes = .background

    @Parameter(
        title: "Search",
        requestValueDialog: IntentDialog("What Codex accounts should I search for?")
    )
    var search: String

    static var parameterSummary: some ParameterSummary {
        Summary("Find accounts matching \(\.$search)")
    }

    nonisolated func perform() async throws -> some IntentResult & ReturnsValue<[CodexAccountEntity]> & ProvidesDialog {
        let trimmedSearch = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSearch.isEmpty else {
            throw $search.needsValueError(
                IntentDialog("Provide an account name, email, or identifier to search for.")
            )
        }

        let state = try CodexSharedAccountIntentResolver.loadState()
        let accounts: [CodexAccountEntity]

        do {
            accounts = try CodexSharedAccountIntentResolver.matchingEntities(matching: trimmedSearch, in: state)
        } catch CodexSharedIntentLookupError.noMatchingAccounts {
            accounts = []
        }

        return .result(
            value: accounts,
            dialog: IntentDialog("Found \(accounts.count) matching Codex account(s).")
        )
    }
}

struct RemoveAccountIntent: AppIntent {
    static let title: LocalizedStringResource = "Remove Codex Account"
    static let description = IntentDescription("Opens Codex Switcher and removes one saved account.")
    static let supportedModes: IntentModes = .foreground

    @Parameter(
        title: "Account",
        requestValueDialog: IntentDialog("Which Codex account should I remove?")
    )
    var account: CodexAccountEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Remove \(\.$account)")
    }

    init() {}

    init(account: CodexAccountEntity) {
        self.account = account
    }

    nonisolated func perform() async throws -> some IntentResult & ReturnsValue<CodexAccountEntity> & ProvidesDialog {
        try await requestConfirmation(
            conditions: [],
            actionName: .custom(
                acceptLabel: "Remove",
                acceptAlternatives: ["Delete"],
                denyLabel: "Cancel",
                denyAlternatives: [],
                destructive: true
            ),
            dialog: IntentDialog("Remove \"\(account.name)\" from Codex Switcher?")
        )

        let command = CodexSharedAppCommand(
            action: .removeAccount,
            accountIdentityKey: account.id,
            expectsResult: true
        )
        let result = try await awaitQueuedCommandResult(for: command)
        defer { try? CodexSharedAppCommandResultStore().remove(commandID: command.id) }

        guard result.status == .success else {
            throw CodexSharedIntentExecutionError.commandFailed(
                result.message ?? "Codex Switcher couldn't remove \"\(account.name)\"."
            )
        }

        let dialogMessage = result.message ?? "Removed \"\(account.name)\"."
        return .result(
            value: account,
            dialog: IntentDialog(stringLiteral: dialogMessage)
        )
    }
}

struct SwitchAccountIntent: AppIntent {
    static let title: LocalizedStringResource = "Switch Codex Account"
    static let description = IntentDescription("Switches Codex to one of your saved accounts.")
    static let supportedModes: IntentModes = .background

    @Parameter(
        title: "Account",
        requestValueDialog: IntentDialog("Which Codex account should I switch to?")
    )
    var account: CodexAccountEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Switch to \(\.$account)")
    }

    init() {}

    init(account: CodexAccountEntity) {
        self.account = account
    }

    nonisolated func perform() async throws -> some IntentResult & ReturnsValue<CodexAccountEntity> & ProvidesDialog {
        do {
            let outcome = try CodexSharedAccountSwitchService().switchToAccount(identityKey: account.id)
            let switchedAccount = CodexAccountEntity(
                record: outcome.account,
                currentAccountID: outcome.account.id
            )

            if outcome.didChangeAccount {
                await CodexSharedSwitchFeedback.postLocalSwitchNotificationIfAuthorized(
                    accountName: outcome.account.name
                )
            }

            return .result(
                value: switchedAccount,
                dialog: IntentDialog(
                    outcome.didChangeAccount
                        ? "Now using \"\(outcome.account.name)\"."
                        : "Already using \"\(outcome.account.name)\"."
                )
            )
        } catch {
            throw mappedSwitchIntentError(from: error)
        }
    }
}

struct SwitchAccountControlIntent: AppIntent, ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Switch Codex Account"
    static let description = IntentDescription("Switches Codex to one of your saved accounts.")
    static let supportedModes: IntentModes = .background
    static let isDiscoverable = false

    @Parameter(title: "Account")
    var account: CodexAccountEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Switch to \(\.$account)")
    }

    nonisolated func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let account else {
            throw $account.needsValueError(IntentDialog("Choose an account first."))
        }

        do {
            let outcome = try CodexSharedAccountSwitchService().switchToAccount(identityKey: account.id)

            if outcome.didChangeAccount {
                await CodexSharedSwitchFeedback.postLocalSwitchNotificationIfAuthorized(
                    accountName: outcome.account.name
                )
            }

            return .result(
                dialog: IntentDialog(
                    outcome.didChangeAccount
                        ? "Now using \"\(outcome.account.name)\"."
                        : "Already using \"\(outcome.account.name)\"."
                )
            )
        } catch {
            throw mappedSwitchIntentError(from: error)
        }
    }
}

struct SwitchToBestAccountIntent: AppIntent {
    static let title: LocalizedStringResource = "Switch to Best Codex Account"
    static let description = IntentDescription(
        "Switches to the saved account with the highest remaining 5h and 7d rate-limit headroom."
    )
    static let supportedModes: IntentModes = .background

    nonisolated func perform() async throws -> some IntentResult & ReturnsValue<CodexAccountEntity> & ProvidesDialog {
        do {
            let outcome = try CodexSharedAccountSwitchService().switchToBestAccount()
            let switchedAccount = CodexAccountEntity(
                record: outcome.account,
                currentAccountID: outcome.account.id
            )

            if outcome.didChangeAccount {
                await CodexSharedSwitchFeedback.postLocalSwitchNotificationIfAuthorized(
                    accountName: outcome.account.name
                )
            }

            return .result(
                value: switchedAccount,
                dialog: IntentDialog(
                    outcome.didChangeAccount
                        ? "Now using \"\(outcome.account.name)\", your best available account."
                        : "Already using \"\(outcome.account.name)\", your best available account."
                )
            )
        } catch {
            throw mappedSwitchIntentError(from: error)
        }
    }
}

struct OpenCodexSwitcherIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Codex Switcher"
    static let description = IntentDescription("Opens Codex Switcher.")
    static let supportedModes: IntentModes = .foreground

    nonisolated func perform() async throws -> some IntentResult {
        .result()
    }
}

struct QuitCodexSwitcherIntent: AppIntent {
    static let title: LocalizedStringResource = "Quit Codex Switcher"
    static let description = IntentDescription("Quits Codex Switcher if it is currently running.")
    static let supportedModes: IntentModes = .background

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

private nonisolated func awaitQueuedCommandResult(
    for command: CodexSharedAppCommand
) async throws -> CodexSharedAppCommandResult {
    let resultStore = CodexSharedAppCommandResultStore()
    try? resultStore.remove(commandID: command.id)
    try CodexSharedAppCommandQueue().enqueue(command)
    CodexSharedAppCommandSignal.postCommandQueuedSignal()
    return try await resultStore.waitForResult(commandID: command.id)
}

private nonisolated func mappedSwitchIntentError(from error: Error) -> Error {
    guard let error = error as? CodexSharedSwitchError else {
        return error
    }

    switch error {
    case .missingBookmark,
         .accessDenied,
         .linkedFolderUnavailable,
         .verificationFailed,
         .unreadable,
         .unwritable,
         .unsupportedAuthState(.unlinked),
         .unsupportedAuthState(.locationUnavailable),
         .unsupportedAuthState(.accessDenied),
         .unsupportedAuthState(.unsupportedCredentialStore):
        return AppIntentError.UserActionRequired.accountSetup

    case .unsupportedAuthState(.loggedOut), .unsupportedAuthState(.corruptAuthFile):
        return AppIntentError.UserActionRequired.signin

    case .accountSelectionRequired,
         .accountNotFound,
         .noBestAccountAvailable,
         .missingStoredSnapshot,
         .invalidStoredSnapshot,
         .unsupportedAuthState(.ready):
        return error
    }
}
