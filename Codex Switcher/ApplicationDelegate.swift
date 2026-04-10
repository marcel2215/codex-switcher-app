//
//  ApplicationDelegate.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-07.
//

import AppKit

final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    /// Tracks whether the user wants Codex Switcher to remain available from
    /// the menu bar after all windows are closed.
    private(set) var keepsRunningInMenuBar = true
    private(set) var keepsRunningForAutopilot = false

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
}
