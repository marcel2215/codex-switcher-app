//
//  CodexSharedAppIntents.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-08.
//

import AppIntents
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

struct CodexAccountEntityQuery: EntityQuery {
    nonisolated func entities(for identifiers: [String]) async throws -> [CodexAccountEntity] {
        let state = try CodexSharedStateStore().load()
        let entitiesByIdentifier = Dictionary(
            uniqueKeysWithValues: state.accounts.map { ($0.id, CodexAccountEntity(record: $0, currentAccountID: state.currentAccountID)) }
        )

        return identifiers.compactMap { entitiesByIdentifier[$0] }
    }

    nonisolated func suggestedEntities() async throws -> [CodexAccountEntity] {
        let state = try CodexSharedStateStore().load()
        return state.accounts.map { CodexAccountEntity(record: $0, currentAccountID: state.currentAccountID) }
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

    nonisolated func perform() async throws -> some IntentResult {
        guard let account else {
            throw CodexSharedSwitchError.accountSelectionRequired
        }

        _ = try CodexSharedAccountSwitchService().switchToAccount(identityKey: account.id)
        return .result()
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
