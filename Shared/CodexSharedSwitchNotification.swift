//
//  CodexSharedSwitchNotification.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-11.
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
            content.title = "Account Switched"
            content.body = "Now using \"\(trimmedAccountName)\"."
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
