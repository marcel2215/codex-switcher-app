//
//  ApplicationDelegate.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-07.
//

import AppKit
import OSLog
import UserNotifications

final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    /// Tracks whether the user wants Codex Switcher to remain available from
    /// the menu bar after all windows are closed.
    private(set) var keepsRunningInMenuBar = true
    private(set) var keepsRunningForAutopilot = false
    private let singleInstanceCoordinator = AppSingleInstanceCoordinator()
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "CodexSwitcher",
        category: "ApplicationDelegate"
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        let notificationCenter = UNUserNotificationCenter.current()
        notificationCenter.delegate = self

        Task {
            await CodexNotificationAuthorization.ensureProvidesAppNotificationSettingsIfAuthorized(
                center: notificationCenter
            )
        }

        do {
            let terminatedInstances = try singleInstanceCoordinator.requestTerminationOfOlderInstances()
            guard !terminatedInstances.isEmpty else {
                return
            }

            logger.info("Requested termination of \(terminatedInstances.count) older Codex Switcher instance(s).")
        } catch {
            logger.error(
                "Couldn't enforce single-instance launch policy: \(String(describing: error), privacy: .private)"
            )
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !(keepsRunningInMenuBar || keepsRunningForAutopilot)
    }

    func applyMenuBarPreference(isEnabled: Bool) {
        applyBackgroundResidency(
            menuBarEnabled: isEnabled,
            autopilotEnabled: keepsRunningForAutopilot
        )
    }

    func applyBackgroundResidency(menuBarEnabled: Bool, autopilotEnabled: Bool) {
        keepsRunningInMenuBar = menuBarEnabled
        keepsRunningForAutopilot = autopilotEnabled

        // Without a menu bar extra, keep the Dock icon available so the app
        // remains reachable while background Autopilot continues to run.
        if !menuBarEnabled {
            restoreForegroundPresentation()
        }
    }

    func handlePrimaryQuitCommand() {
        guard keepsRunningInMenuBar || keepsRunningForAutopilot else {
            NSApp.terminate(nil)
            return
        }

        if keepsRunningInMenuBar {
            guard NSApp.setActivationPolicy(.accessory) else {
                NSApp.terminate(nil)
                return
            }
        } else {
            restoreForegroundPresentation()
        }

        for window in NSApp.windows where window.isVisible {
            window.performClose(nil)
        }
    }

    func restoreForegroundPresentation() {
        guard NSApp.activationPolicy() != .regular else {
            return
        }

        _ = NSApp.setActivationPolicy(.regular)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        restoreForegroundPresentation()
        return true
    }

    @MainActor
    private func openNotificationSettings() {
        restoreForegroundPresentation()
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

extension ApplicationDelegate: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        openSettingsFor notification: UNNotification?
    ) {
        Task { @MainActor in
            openNotificationSettings()
        }
    }
}
