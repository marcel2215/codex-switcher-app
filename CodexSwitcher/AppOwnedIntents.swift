//
//  CodexSwitcherAppOwnedIntents.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-10.
//

import AppIntents

/// Keep Siri/Shortcuts actions in the main app bundle so the system can
/// background-launch Codex Switcher and reuse the app's durable
/// security-scoped bookmark. Widget and control intents stay in `Shared`
/// because those surfaces legitimately execute out of process.
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
            intent: OpenCodexAccountIntent(),
            phrases: [
                "Open \(\.$target) in \(.applicationName)",
                "Show \(\.$target) in \(.applicationName)",
            ],
            shortTitle: "Open Account",
            systemImageName: "person.text.rectangle"
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

struct GetCurrentCodexRateLimitsIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Current Codex Rate Limits"
    static let description = IntentDescription(
        "Returns the latest saved 5h and 7d remaining rate limits for the current Codex account."
    )
    static let supportedModes: IntentModes = .background

    nonisolated func perform() async throws -> some IntentResult & ReturnsValue<CodexAccountEntity> & ProvidesDialog {
        let state = try CodexSharedAccountIntentResolver.loadState()
        let account = try CodexSharedAccountIntentResolver.currentEntity(in: state)

        return .result(
            value: account,
            dialog: rateLimitDialog(for: account, prefix: "Current account")
        )
    }
}

struct GetCodexAccountRateLimitsIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Codex Account Rate Limits"
    static let description = IntentDescription(
        "Returns the latest saved 5h and 7d remaining rate limits for one saved Codex account."
    )
    static let supportedModes: IntentModes = .background

    @Parameter(
        title: "Account",
        requestValueDialog: IntentDialog("Which Codex account should I get rate limits for?")
    )
    var account: CodexAccountEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Get rate limits for \(\.$account)")
    }

    init() {}

    init(account: CodexAccountEntity) {
        self.account = account
    }

    nonisolated func perform() async throws -> some IntentResult & ReturnsValue<CodexAccountEntity> & ProvidesDialog {
        let state = try CodexSharedAccountIntentResolver.loadState()
        let refreshedAccount = try resolveLiveAccountEntity(for: account, in: state)

        return .result(
            value: refreshedAccount,
            dialog: rateLimitDialog(for: refreshedAccount, prefix: "Rate limits")
        )
    }
}

struct GetBestCodexRateLimitsIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Best Codex Rate Limits"
    static let description = IntentDescription(
        "Returns the latest saved rate limits for the account with the most remaining headroom."
    )
    static let supportedModes: IntentModes = .background

    nonisolated func perform() async throws -> some IntentResult & ReturnsValue<CodexAccountEntity> & ProvidesDialog {
        let state = try CodexSharedAccountIntentResolver.loadState()
        let account = try CodexSharedAccountIntentResolver.bestEntity(in: state)

        return .result(
            value: account,
            dialog: rateLimitDialog(for: account, prefix: "Best available account")
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
        let command = CodexSharedAppCommand(
            action: .switchAccount,
            accountIdentityKey: account.id,
            expectsResult: true
        )
        let result = try await awaitQueuedCommandResult(for: command)
        defer { try? CodexSharedAppCommandResultStore().remove(commandID: command.id) }

        guard result.status == .success else {
            throw CodexSharedIntentExecutionError.commandFailed(
                result.message ?? "Codex Switcher couldn't switch accounts."
            )
        }

        let state = try CodexSharedAccountIntentResolver.loadState()
        let switchedAccount = try resolveLiveAccountEntity(for: account, in: state)

        return .result(
            value: switchedAccount,
            dialog: IntentDialog(
                stringLiteral: result.message
                    ?? "Now using \"\(switchedAccount.name)\"."
            )
        )
    }
}

struct SwitchToBestAccountIntent: AppIntent {
    static let title: LocalizedStringResource = "Switch to Best Codex Account"
    static let description = IntentDescription(
        "Switches to the saved account with the highest remaining 5h and 7d rate-limit headroom."
    )
    static let supportedModes: IntentModes = .background

    nonisolated func perform() async throws -> some IntentResult & ReturnsValue<CodexAccountEntity> & ProvidesDialog {
        let command = CodexSharedAppCommand(
            action: .switchBestAccount,
            expectsResult: true
        )
        let result = try await awaitQueuedCommandResult(for: command)
        defer { try? CodexSharedAppCommandResultStore().remove(commandID: command.id) }

        guard result.status == .success else {
            throw CodexSharedIntentExecutionError.commandFailed(
                result.message ?? "Codex Switcher couldn't switch to the best available account."
            )
        }

        let state = try CodexSharedAccountIntentResolver.loadState()
        let switchedAccount = try CodexSharedAccountIntentResolver.bestEntity(in: state)

        return .result(
            value: switchedAccount,
            dialog: IntentDialog(
                stringLiteral: result.message
                    ?? "Now using \"\(switchedAccount.name)\", your best available account."
            )
        )
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

/// Foreground intents must wait for the app-owned mutation to finish before
/// returning, otherwise the next Shortcuts step can observe stale shared state.
private nonisolated func awaitQueuedCommandResult(
    for command: CodexSharedAppCommand
) async throws -> CodexSharedAppCommandResult {
    let resultStore = CodexSharedAppCommandResultStore()
    try? resultStore.remove(commandID: command.id)
    try CodexSharedAppCommandQueue().enqueue(command)
    CodexSharedAppCommandSignal.postCommandQueuedSignal()
    return try await resultStore.waitForResult(commandID: command.id)
}

private nonisolated func resolveLiveAccountEntity(
    for parameter: CodexAccountEntity,
    in state: SharedCodexState
) throws -> CodexAccountEntity {
    if let refreshedAccount = CodexSharedAccountIntentResolver.entity(withIdentityKey: parameter.id, in: state) {
        return refreshedAccount
    }

    throw CodexSharedIntentLookupError.noMatchingAccount(parameter.name)
}

private nonisolated func rateLimitDialog(
    for account: CodexAccountEntity,
    prefix: String
) -> IntentDialog {
    let message = [
        "\(prefix): \"\(account.name)\".",
        "5-hour remaining: \(formattedRemainingPercent(account.fiveHourLimitUsedPercent)).",
        "7-day remaining: \(formattedRemainingPercent(account.sevenDayLimitUsedPercent)).",
    ]
    .joined(separator: " ")

    return IntentDialog(stringLiteral: message)
}

private nonisolated func formattedRemainingPercent(_ value: Int?) -> String {
    guard let value else {
        return "unknown"
    }

    return "\(min(max(value, 0), 100))%"
}
