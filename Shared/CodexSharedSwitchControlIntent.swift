//
//  CodexSharedSwitchControlIntent.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-12.
//

@preconcurrency import AppIntents
import Foundation
#if canImport(AppKit)
import AppKit
#endif

struct SwitchAccountControlIntent: AppIntent, ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Switch Codex Account"
    static let description = IntentDescription("Switches Codex to one of your saved accounts.")
    static let supportedModes: IntentModes = .background
    static let isDiscoverable = false

    @Parameter(title: "Account")
    var account: CodexAccountEntity?

    init() {}

    init(account: CodexAccountEntity) {
        self.account = account
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Switch to \(\.$account)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
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

struct SelectConfiguredAccountControlIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Select Codex Account"
    static let description = IntentDescription(
        "Turns this control on when its account is the one currently active in Codex."
    )
    static let supportedModes: IntentModes = .background
    static let isDiscoverable = false

    @Parameter(title: "Selected")
    var value: Bool

    // Keep the toggle action payload primitive and required. Control widgets
    // can preview configuration intents with optional entities, but the action
    // itself needs a concrete identifier when the user toggles the control.
    @Parameter(title: "Account ID")
    var accountID: String

    init() {
        self.accountID = ""
    }

    init(accountID: String) {
        self.accountID = accountID
    }

    func perform() async throws -> some IntentResult {
        let trimmedAccountID = accountID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAccountID.isEmpty else {
            throw AppIntentError.UserActionRequired.accountSetup
        }

        // Control Center renders this as a toggle, but the domain model is an
        // exclusive account selector. Treat any user interaction as "select
        // this account" instead of honoring the transient boolean verbatim,
        // otherwise the control can no-op when the system delivers an off-state
        // update for a control that should really behave like a radio button.

        let command = CodexSharedAppCommand(
            action: .switchAccount,
            accountIdentityKey: trimmedAccountID,
            expectsResult: true
        )

        do {
            let result = try await awaitQueuedSharedAppCommandResult(for: command)
            defer { try? CodexSharedAppCommandResultStore().remove(commandID: command.id) }

            guard result.status == .success else {
                throw CodexSharedIntentExecutionError.commandFailed(
                    result.message ?? "Codex Switcher couldn't switch accounts."
                )
            }

            return .result()
        } catch let error as CodexSharedIntentExecutionError {
            throw error
        } catch {
            throw mappedSwitchIntentError(from: error)
        }
    }
}

private nonisolated func awaitQueuedSharedAppCommandResult(
    for command: CodexSharedAppCommand
) async throws -> CodexSharedAppCommandResult {
    let resultStore = CodexSharedAppCommandResultStore()
    try? resultStore.remove(commandID: command.id)
    try CodexSharedAppCommandQueue().enqueue(command)
    try await ensureMainApplicationRunningIfNeeded()
    CodexSharedAppCommandSignal.postCommandQueuedSignal()
    return try await resultStore.waitForResult(commandID: command.id)
}

#if canImport(AppKit)
private nonisolated func ensureMainApplicationRunningIfNeeded() async throws {
    guard !CodexSharedAppCommandSignal.isMainApplicationRunning else {
        return
    }

    // Control actions execute in the widget/control extension process by
    // default. Queue the app-owned command, then launch the containing app in
    // the background so its startup path can drain the queue without stealing
    // focus from Control Center.
    let appURL = Bundle.main.bundleURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    configuration.addsToRecentItems = false
    configuration.allowsRunningApplicationSubstitution = true
    configuration.createsNewApplicationInstance = false
    configuration.hides = true
    configuration.promptsUserIfNeeded = false
    _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
}
#else
private nonisolated func ensureMainApplicationRunningIfNeeded() async throws {}
#endif

nonisolated private func mappedSwitchIntentError(from error: Error) -> Error {
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
