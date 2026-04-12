//
//  CodexWidgetEntities.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-12.
//

import AppIntents
import Foundation

struct WidgetCodexAccountEntity: AppEntity, Identifiable, Hashable, Sendable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Codex Account")
    static let defaultQuery = WidgetCodexAccountEntityQuery()

    let id: String
    let name: String
    let iconSystemName: String
    let isMissing: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: name),
            image: .init(systemName: iconSystemName)
        )
    }

    static func live(from record: SharedCodexAccountRecord) -> Self {
        Self(
            id: record.id,
            name: record.name,
            iconSystemName: record.iconSystemName,
            isMissing: false
        )
    }

    static func missing(id: String) -> Self {
        Self(
            id: id,
            name: "Missing Account",
            iconSystemName: "questionmark.circle.fill",
            isMissing: true
        )
    }
}

struct WidgetCodexAccountEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [WidgetCodexAccountEntity] {
        let state = (try? CodexSharedStateStore().load()) ?? .empty

        return identifiers.map { identifier in
            if let record = state.account(withIdentityKey: identifier) {
                return .live(from: record)
            }

            return .missing(id: identifier)
        }
    }

    func suggestedEntities() async throws -> [WidgetCodexAccountEntity] {
        let state = (try? CodexSharedStateStore().load()) ?? .empty
        return state.accounts
            .sorted(by: widgetAccountComparator)
            .map(WidgetCodexAccountEntity.live(from:))
    }

    func entities(matching string: String) async throws -> [WidgetCodexAccountEntity] {
        let state = (try? CodexSharedStateStore().load()) ?? .empty
        let query = string.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !query.isEmpty else {
            return []
        }

        return state.accounts
            .filter { record in
                record.name.localizedCaseInsensitiveContains(query)
                    || (record.emailHint?.localizedCaseInsensitiveContains(query) == true)
                    || (record.accountIdentifier?.localizedCaseInsensitiveContains(query) == true)
            }
            .sorted(by: widgetAccountComparator)
            .map(WidgetCodexAccountEntity.live(from:))
    }

    private func widgetAccountComparator(
        lhs: SharedCodexAccountRecord,
        rhs: SharedCodexAccountRecord
    ) -> Bool {
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }

        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}
