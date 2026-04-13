//
//  IOSApplicationDelegate.swift
//  Codex Switcher iOS App
//
//  Created by Codex on 2026-04-14.
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

        return true
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
