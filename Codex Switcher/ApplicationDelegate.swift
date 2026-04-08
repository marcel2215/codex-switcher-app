//
//  ApplicationDelegate.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-07.
//

import AppKit

final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    /// The app now owns a persistent MenuBarExtra. Closing the main window
    /// should leave the process alive so widgets, controls, and the menu bar
    /// surface keep working.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
