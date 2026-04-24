//
//  SwitchControlIntent.swift
//  Codex Switcher
//
//  Created by Marcel Kwiatkowski on 2026-04-12.
//

@preconcurrency import AppIntents
import Foundation

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
        // exclusive account selector. Turning one account on means "make this
        // account current". Turning the active account off is a no-op because
        // the app always has one current account.
        guard value else {
            return .result()
        }

        do {
            let outcome = try await CodexSharedAccountSwitchService()
                .switchToAccount(identityKey: trimmedAccountID)

            if outcome.didChangeAccount {
                await CodexSharedSwitchFeedback.postLocalSwitchNotificationIfAuthorized(
                    accountName: outcome.account.name
                )
            }

            return .result()
        } catch {
            throw mappedSwitchIntentError(from: error)
        }
    }
}

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
         .unsupportedCredentialStore,
         .unsupportedAuthState(.unlinked),
         .unsupportedAuthState(.locationUnavailable),
         .unsupportedAuthState(.accessDenied),
         .unsupportedAuthState(.unsupportedCredentialStore):
        return AppIntentError.UserActionRequired.accountSetup

    case .unsupportedAuthState(.loggedOut), .unsupportedAuthState(.corruptAuthFile):
        return AppIntentError.UserActionRequired.signin

    case .accountSelectionRequired,
         .accountNotFound,
         .accountUnavailable,
         .noBestAccountAvailable,
         .missingStoredSnapshot,
         .invalidStoredSnapshot,
         .unsupportedAuthState(.ready):
        return error
    }
}
