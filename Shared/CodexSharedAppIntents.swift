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

    @Property(title: "Available On This Mac")
    var hasLocalSnapshot: Bool

    var iconSystemName: String
    var sortOrder: Double

    nonisolated var displayRepresentation: DisplayRepresentation {
        let subtitleParts = [
            isCurrent ? "Current" : nil,
            hasLocalSnapshot ? nil : "Needs local capture on this Mac",
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
            hasLocalSnapshot ? nil : "Needs local capture on this Mac",
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
            hasLocalSnapshot ? "Available" : "Needs local capture",
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
        self.hasLocalSnapshot = record.hasLocalSnapshot
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

    init() {}

    init(account: CodexAccountEntity) {
        self.account = account
    }

    nonisolated func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let account else {
            throw $account.needsValueError(IntentDialog("Choose an account first."))
        }

        do {
            let outcome = try await CodexSharedAccountSwitchService().switchToAccount(identityKey: account.id)

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

struct OpenCodexSwitcherIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Codex Switcher"
    static let description = IntentDescription("Opens Codex Switcher.")
    static let supportedModes: IntentModes = .foreground

    nonisolated func perform() async throws -> some IntentResult {
        .result()
    }
}

nonisolated func mappedSwitchIntentError(from error: Error) -> Error {
    guard let error = error as? CodexSharedSwitchError else {
        return error
    }

    switch error {
    case .missingBookmark,
         .bookmarkRefreshRequired,
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
