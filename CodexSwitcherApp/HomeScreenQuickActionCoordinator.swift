//
//  IOSHomeScreenQuickActionCoordinator.swift
//  Codex Switcher iOS App
//
//  Created by Codex on 2026-04-14.
//

import Observation
import UIKit

@MainActor
@Observable
final class IOSHomeScreenQuickActionCoordinator {
    // SpringBoard surfaces up to four quick actions for an app icon.
    nonisolated static let maximumAccountQuickActions = 4
    static let shared = IOSHomeScreenQuickActionCoordinator()

    private static let accountIDUserInfoKey = "accountID"
    private static let quickActionType = "\(Bundle.main.bundleIdentifier ?? "CodexSwitcher").open-account-detail"

    private(set) var pendingAccountDetailID: UUID?

    func shortcutItems(
        from accounts: [IOSHomeScreenQuickActionAccountItem]
    ) -> [UIApplicationShortcutItem] {
        accounts.map { account in
            UIApplicationShortcutItem(
                type: Self.quickActionType,
                localizedTitle: account.title,
                localizedSubtitle: account.subtitle,
                icon: UIApplicationShortcutIcon(systemImageName: account.iconSystemName),
                userInfo: [Self.accountIDUserInfoKey: account.id.uuidString as NSString]
            )
        }
    }

    func updateShortcutItems(
        from accounts: [IOSHomeScreenQuickActionAccountItem]
    ) {
        UIApplication.shared.shortcutItems = shortcutItems(from: accounts)
    }

    func handleShortcutItem(_ shortcutItem: UIApplicationShortcutItem) -> Bool {
        guard let accountID = accountID(from: shortcutItem) else {
            return false
        }

        pendingAccountDetailID = accountID
        return true
    }

    func clearPendingAccountDetailID(ifMatching accountID: UUID) {
        guard pendingAccountDetailID == accountID else {
            return
        }

        pendingAccountDetailID = nil
    }

    private func accountID(from shortcutItem: UIApplicationShortcutItem) -> UUID? {
        guard shortcutItem.type == Self.quickActionType else {
            return nil
        }

        if let accountIDString = shortcutItem.userInfo?[Self.accountIDUserInfoKey] as? String {
            return UUID(uuidString: accountIDString)
        }

        if let accountIDString = shortcutItem.userInfo?[Self.accountIDUserInfoKey] as? NSString {
            return UUID(uuidString: accountIDString as String)
        }

        return nil
    }
}
