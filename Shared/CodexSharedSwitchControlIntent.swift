//
//  CodexSharedSwitchControlIntent.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-12.
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
