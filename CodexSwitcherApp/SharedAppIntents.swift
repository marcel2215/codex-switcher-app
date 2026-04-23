//
//  SharedAppIntents.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-08.
//

@preconcurrency import AppIntents
import SwiftUI
import WidgetKit

#if canImport(CoreSpotlight)
import CoreSpotlight
typealias CodexIndexedEntityProtocol = IndexedEntity
#else
protocol CodexIndexedEntityProtocol {}
#endif

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

struct CodexAccountEntity: AppEntity, CodexIndexedEntityProtocol, Hashable, Sendable {
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

    @Property(title: "Pinned")
    var isPinned: Bool

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
            isPinned ? "Pinned" : nil,
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

#if canImport(CoreSpotlight)
    nonisolated var attributeSet: CSSearchableItemAttributeSet {
        let attributeSet = defaultAttributeSet
        attributeSet.displayName = name
        attributeSet.contentDescription = [
            isCurrent ? "Current account" : nil,
            isPinned ? "Pinned account" : nil,
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
            isPinned ? "Pinned" : nil,
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
#endif

    nonisolated init(record: SharedCodexAccountRecord, currentAccountID: String?) {
        self.id = record.id
        self.iconSystemName = record.iconSystemName
        self.sortOrder = record.sortOrder
        self.name = record.name
        self.emailHint = record.emailHint
        self.accountIdentifier = record.accountIdentifier
        self.isCurrent = record.id == currentAccountID
        self.isPinned = record.isPinned
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
        if lhs.isPinned != rhs.isPinned {
            return lhs.isPinned && !rhs.isPinned
        }

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
}
