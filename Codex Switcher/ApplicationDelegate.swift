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

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !keepsRunningInMenuBar
    }

    func applyMenuBarPreference(isEnabled: Bool) {
        keepsRunningInMenuBar = isEnabled

        // If the menu bar mode was turned off while the app was running as an
        // accessory, immediately restore the Dock icon so the app doesn't
        // become unreachable.
        if !isEnabled {
            restoreForegroundPresentation()
        }
    }

    func handlePrimaryQuitCommand() {
        guard keepsRunningInMenuBar else {
            NSApp.terminate(nil)
            return
        }

        guard NSApp.setActivationPolicy(.accessory) else {
            NSApp.terminate(nil)
            return
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
