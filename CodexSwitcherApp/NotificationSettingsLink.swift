//
//  NotificationSettingsLink.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-13.
//

import Foundation
@preconcurrency import UserNotifications

#if os(iOS)
import UIKit
#endif

enum CodexNotificationSettingsLink {
    nonisolated static func sectionFooterURL(
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.marcel2215.codexswitcher"
    ) -> URL? {
#if os(iOS)
        return URL(string: UIApplication.openNotificationSettingsURLString)
#elseif os(macOS)
        // macOS doesn't currently expose a dedicated API like iOS for opening
        // an app's notification settings directly, so fall back to the System
        // Settings deep link that targets the Notifications pane for this app.
        let encodedBundleIdentifier = bundleIdentifier.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
        ) ?? bundleIdentifier
        return URL(
            string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(encodedBundleIdentifier)"
        ) ?? URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
#else
        return nil
#endif
    }

    nonisolated static func shouldShowDisabledFooter(
        for authorizationStatus: UNAuthorizationStatus
    ) -> Bool {
        authorizationStatus == .denied
    }
}
