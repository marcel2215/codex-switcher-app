//
//  ApplicationDelegate.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-07.
//

import AppKit

final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    /// This app is intentionally single-window. Closing the last window should
    /// terminate the process instead of leaving a menu-bar-only app behind.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
