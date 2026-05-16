//
//  WidgetEntities.swift
//  Codex Switcher
//
//  Created by Marcel Kwiatkowski on 2026-04-12.
//

import AppIntents
import Foundation

struct WidgetCodexAccountEntity: AppEntity, Identifiable, Hashable, Sendable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Codex Account")
    static let defaultQuery = WidgetCodexAccountEntityQuery()
    static let automaticID = "__automatic__"

    let id: String
    let name: String
    let iconSystemName: String
    let isMissing: Bool
    let isAutomatic: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: name),
            image: .init(systemName: iconSystemName)
        )
    }

    static let automatic = Self(
        id: automaticID,
        name: L10n.string("Automatic", comment: "Widget account picker option that lets the app choose an account automatically."),
        iconSystemName: "arrow.up.arrow.down.circle",
        isMissing: false,
        isAutomatic: true
    )

    static func live(from record: SharedCodexAccountRecord) -> Self {
        Self(
            id: record.id,
            name: record.name,
            iconSystemName: record.iconSystemName,
            isMissing: false,
            isAutomatic: false
        )
    }

    static func missing(id: String) -> Self {
        Self(
            id: id,
            name: L10n.string("Missing Account", comment: "Widget fallback name for an account that no longer exists."),
            iconSystemName: "questionmark.circle.fill",
            isMissing: true,
            isAutomatic: false
        )
    }
}

struct WidgetCodexAccountEntityQuery: EntityQuery, EntityStringQuery, EnumerableEntityQuery {
    func allEntities() async throws -> [WidgetCodexAccountEntity] {
        let state = CodexSharedStateStore().loadBestEffort()
        return allEntities(in: state)
    }

    func defaultResult() async -> WidgetCodexAccountEntity? {
        // WidgetKit consults the entity query for a default configurable value.
        // Returning an explicit Automatic entity avoids unresolved widget
        // configurations on iOS/watchOS when the user adds a widget before
        // selecting a concrete account.
        .automatic
    }

    func entities(for identifiers: [String]) async throws -> [WidgetCodexAccountEntity] {
        let state = CodexSharedStateStore().loadBestEffort()

        return identifiers.map { identifier in
            if identifier == WidgetCodexAccountEntity.automaticID {
                return .automatic
            }

            if let record = state.account(withIdentityKey: identifier) {
                return .live(from: record)
            }

            return .missing(id: identifier)
        }
    }

    func suggestedEntities() async throws -> [WidgetCodexAccountEntity] {
        let state = CodexSharedStateStore().loadBestEffort()
        return allEntities(in: state)
    }

    func entities(matching string: String) async throws -> [WidgetCodexAccountEntity] {
        let state = CodexSharedStateStore().loadBestEffort()
        let query = string.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !query.isEmpty else {
            return []
        }

        var matches: [WidgetCodexAccountEntity] = []

        if "automatic".localizedCaseInsensitiveContains(query)
            || L10n.string("automatic", comment: "Search synonym for the automatic widget account option.").localizedCaseInsensitiveContains(query)
            || "default".localizedCaseInsensitiveContains(query)
            || "auto".localizedCaseInsensitiveContains(query)
        {
            matches.append(.automatic)
        }

        matches.append(contentsOf: state.accounts
            .filter { record in
                record.name.localizedCaseInsensitiveContains(query)
                    || (record.emailHint?.localizedCaseInsensitiveContains(query) == true)
                    || (record.accountIdentifier?.localizedCaseInsensitiveContains(query) == true)
            }
            .sorted(by: widgetAccountComparator)
            .map(WidgetCodexAccountEntity.live(from:))
        )

        return matches
    }

    private func widgetAccountComparator(
        lhs: SharedCodexAccountRecord,
        rhs: SharedCodexAccountRecord
    ) -> Bool {
        AccountsPresentationLogic.sharedAccountRecordComparator(lhs: lhs, rhs: rhs)
    }

    private func allEntities(in state: SharedCodexState) -> [WidgetCodexAccountEntity] {
        [.automatic] + state.accounts
            .sorted(by: widgetAccountComparator)
            .map(WidgetCodexAccountEntity.live(from:))
    }
}
