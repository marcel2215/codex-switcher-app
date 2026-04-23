//
//  WindowSceneDelegate.swift
//  Codex Switcher
//
//  Created by Marcel Kwiatkowski on 2026-04-14.
//

import UIKit

final class IOSWindowSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let shortcutItem = connectionOptions.shortcutItem else {
            return
        }

        _ = IOSHomeScreenQuickActionCoordinator.shared.handleShortcutItem(shortcutItem)
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(
            IOSHomeScreenQuickActionCoordinator.shared.handleShortcutItem(shortcutItem)
        )
    }
}
