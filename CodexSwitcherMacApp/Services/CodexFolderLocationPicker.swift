//
//  CodexFolderLocationPicker.swift
//  Codex Switcher Mac App
//
//  Created by OpenAI on 2026-04-24.
//

import AppKit
import Foundation

@MainActor
protocol CodexFolderLocationPicking {
    func pickCodexFolder() async -> URL?
}

@MainActor
final class CodexFolderLocationPicker: CodexFolderLocationPicking {
    private var activePanel: NSOpenPanel?

    func pickCodexFolder() async -> URL? {
        if let activePanel {
            activePanel.makeKeyAndOrderFront(nil)
            return nil
        }

        return await withCheckedContinuation { continuation in
            let panel = NSOpenPanel()
            panel.title = "Select Codex Folder"
            panel.message = "Choose the .codex folder that contains auth.json."
            panel.prompt = "Link Folder"
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.canCreateDirectories = true
            panel.resolvesAliases = true
            panel.showsHiddenFiles = true
            panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser

            activePanel = panel

            let completion: (NSApplication.ModalResponse) -> Void = { [weak self, weak panel] response in
                let selectedURL = response == .OK ? panel?.url : nil
                self?.activePanel = nil
                continuation.resume(returning: selectedURL)
            }

            if let presentationWindow = Self.presentationWindow {
                panel.beginSheetModal(for: presentationWindow, completionHandler: completion)
            } else {
                panel.begin(completionHandler: completion)
            }
        }
    }

    private static var presentationWindow: NSWindow? {
        if let keyWindow = NSApp.keyWindow, keyWindow.isVisible {
            return keyWindow
        }

        if let mainWindow = NSApp.mainWindow, mainWindow.isVisible {
            return mainWindow
        }

        return NSApp.windows.first { window in
            window.isVisible && window.canBecomeKey
        }
    }
}
