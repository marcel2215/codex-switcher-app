//
//  ApplicationDelegate.swift
//  Codex Switcher
//
//  Created by Marcel Kwiatkowski on 2026-04-14.
//

import UIKit
import UserNotifications

final class IOSApplicationDelegate: NSObject, UIApplicationDelegate {
    private let notificationCenter = UNUserNotificationCenter.current()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        notificationCenter.delegate = self

        Task {
            await CodexNotificationAuthorization.ensureProvidesAppNotificationSettingsIfAuthorized(
                center: notificationCenter
            )
        }

        IOSBackgroundAppRefreshCoordinator.shared.scheduleNextRefresh()
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: nil,
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = IOSWindowSceneDelegate.self
        return configuration
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        IOSBackgroundAppRefreshCoordinator.shared.scheduleNextRefresh()
    }
}

extension IOSApplicationDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        openSettingsFor notification: UNNotification?
    ) {
        CodexInAppNotificationSettingsSignal.requestOpenNotificationSettings()
    }
}
