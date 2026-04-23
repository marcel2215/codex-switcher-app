//
//  ApplicationDelegate.swift
//  Codex Switcher Mac App
//
//  Created by Marcel Kwiatkowski on 2026-04-07.
//

import AppKit
import OSLog
import UserNotifications

struct DockAccountItem: Equatable, Sendable {
    let id: UUID
    let title: String
    let iconSystemName: String
    let isCurrentAccount: Bool
}

final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    private nonisolated static let dockAccountsMenuLimit = 5

    /// Tracks whether the user wants Codex Switcher to remain available from
    /// the menu bar after all windows are closed.
    private(set) var keepsRunningInMenuBar = true
    private(set) var keepsRunningForAutopilot = false
    private let singleInstanceCoordinator = AppSingleInstanceCoordinator()
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "CodexSwitcher",
        category: "ApplicationDelegate"
    )
    private var dockAccountsProvider: (@MainActor (Int) -> [DockAccountItem])?
    private var dockAccountSelectionHandler: (@MainActor (UUID) -> Void)?

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
    func configureDockAccounts(
        provider: @escaping @MainActor (Int) -> [DockAccountItem],
        onSelect: @escaping @MainActor (UUID) -> Void
    ) {
        dockAccountsProvider = provider
        dockAccountSelectionHandler = onSelect
    }

    @MainActor
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        guard let dockAccountsProvider else {
            return nil
        }

        let menu = NSMenu(title: "Codex Switcher")
        let accounts = dockAccountsProvider(Self.dockAccountsMenuLimit)

        if accounts.isEmpty {
            let emptyStateItem = NSMenuItem(title: "No Switchable Accounts", action: nil, keyEquivalent: "")
            emptyStateItem.isEnabled = false
            menu.addItem(emptyStateItem)
        } else {
            for account in accounts {
                menu.addItem(makeDockAccountMenuItem(for: account))
            }
        }

        return menu
    }

    @MainActor
    private func openNotificationSettings() {
        restoreForegroundPresentation()
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    @MainActor
    @objc private func handleDockAccountMenuSelection(_ sender: NSMenuItem) {
        guard
            let accountIDString = sender.representedObject as? String,
            let accountID = UUID(uuidString: accountIDString)
        else {
            return
        }

        dockAccountSelectionHandler?(accountID)
    }

    @MainActor
    private func makeDockAccountMenuItem(for account: DockAccountItem) -> NSMenuItem {
        let item = NSMenuItem(
            title: account.title,
            action: #selector(handleDockAccountMenuSelection(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.representedObject = account.id.uuidString
        item.state = account.isCurrentAccount ? .on : .off
        item.image = NSImage(
            systemSymbolName: account.iconSystemName,
            accessibilityDescription: account.title
        )
        return item
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
