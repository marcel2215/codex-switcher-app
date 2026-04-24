//
//  CodexDesktopAppObserver.swift
//  Codex Switcher Mac App
//
//  Created by OpenAI on 2026-04-24.
//

import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class CodexDesktopAppObserver {
    struct RunningCodexApp: Identifiable, Hashable {
        let id: pid_t
        let app: NSRunningApplication
        let bundleURL: URL?
    }

    private(set) var runningApps: [RunningCodexApp] = []

    func refresh() {
        runningApps = NSWorkspace.shared.runningApplications.compactMap { app in
            guard Self.looksLikeCodexDesktop(app) else {
                return nil
            }

            return RunningCodexApp(
                id: app.processIdentifier,
                app: app,
                bundleURL: app.bundleURL
            )
        }
    }

    static func looksLikeCodexDesktop(_ app: NSRunningApplication) -> Bool {
        let bundleID = app.bundleIdentifier?.lowercased() ?? ""
        let name = app.localizedName?.lowercased() ?? ""
        let executable = app.executableURL?.lastPathComponent.lowercased() ?? ""

        if bundleID == "com.openai.codex" {
            return true
        }

        if bundleID.hasPrefix("com.openai.codex.") {
            return true
        }

        if name == "codex" {
            return true
        }

        if executable == "codex" {
            return true
        }

        return false
    }
}
