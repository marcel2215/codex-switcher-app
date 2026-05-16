//
//  SwitchNotification.swift
//  Codex Switcher
//
//  Created by Marcel Kwiatkowski on 2026-04-11.
//

import Foundation
import UserNotifications

enum CodexSwitchNotificationKind: Sendable {
    case userInitiated
    case backgroundConfirmation
    case recoveryAttention
}

enum CodexSharedSwitchNotificationContent {
    nonisolated static let threadIdentifier = "account-switch"

    nonisolated static func makeContent(
        accountName: String,
        kind: CodexSwitchNotificationKind
    ) -> UNMutableNotificationContent? {
        let trimmedAccountName = accountName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAccountName.isEmpty else {
            return nil
        }

        switch kind {
        case .userInitiated:
            return nil
        case .backgroundConfirmation, .recoveryAttention:
            let content = UNMutableNotificationContent()
            content.title = L10n.string(
                "Account Switched",
                comment: "Notification title shown after a background account switch."
            )
            content.body = L10n.format(
                "Now using \"%@\".",
                trimmedAccountName,
                comment: "Notification body. The argument is the account name."
            )
            content.sound = nil
            content.threadIdentifier = threadIdentifier

            switch kind {
            case .backgroundConfirmation:
                content.interruptionLevel = .passive
                content.relevanceScore = 0
            case .recoveryAttention:
                content.interruptionLevel = .active
                content.relevanceScore = 0.4
            case .userInitiated:
                break
            }

            return content
        }
    }
}
