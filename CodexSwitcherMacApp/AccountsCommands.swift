//
//  AccountsCommands.swift
//  Codex Switcher Mac App
//
//  Created by Marcel Kwiatkowski on 2026-04-07.
//

import AppKit
import SwiftUI

struct AccountsCommands: Commands {
    let controller: AppController
    let applicationDelegate: ApplicationDelegate
    let showsMenuBarExtra: Bool

    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // Keep standard macOS categories intact, and only use a custom top-level
        // menu for actions that are truly account-specific.
        CommandGroup(replacing: .newItem) {
            Button("Add Account") {
                controller.captureCurrentAccount()
            }
            // This is a single-window utility app, so the File > New command
            // should create a saved account entry rather than open another window.
            .keyboardShortcut("n", modifiers: [.command])
            .disabled(!controller.canCaptureCurrentAccount)

            Divider()

            Button("Import...") {
                controller.beginAccountArchiveImport()
            }
            .keyboardShortcut("o", modifiers: [.command])
        }

        CommandGroup(replacing: .pasteboard) {
            Button("Copy") {
                controller.copySelectedAccountsToPasteboard()
            }
            .keyboardShortcut("c", modifiers: [.command])

            Button("Paste") {
                controller.pasteAccountArchivesFromPasteboard()
            }
            .keyboardShortcut("v", modifiers: [.command])

            Divider()

            Button(role: .destructive) {
                controller.removeSelectedAccounts()
            } label: {
                Label("Remove", systemImage: "trash")
                    .foregroundStyle(.red)
            }
            .keyboardShortcut(.delete, modifiers: [])
            .disabled(controller.selection.isEmpty)
        }

        CommandGroup(after: .toolbar) {
            Divider()

            ForEach(AccountSortCriterion.allCases) { criterion in
                Button {
                    controller.sortCriterion = criterion
                } label: {
                    checkedMenuLabel(
                        title: criterion.menuTitle,
                        isSelected: controller.sortCriterion == criterion
                    )
                }
            }

            if controller.sortCriterion != .custom {
                Divider()

                ForEach(SortDirection.allCases) { direction in
                    Button {
                        controller.sortDirection = direction
                    } label: {
                        checkedMenuLabel(
                            title: direction.menuTitle,
                            isSelected: controller.sortDirection == direction
                        )
                    }
                }
            }

            Divider()

            Button("Clear Search") {
                controller.searchText = ""
            }
            .disabled(controller.searchText.isEmpty)

            Divider()

            Button("Refresh") {
                controller.refresh()
            }
            .keyboardShortcut("r", modifiers: [.command])
        }

        CommandGroup(replacing: .printItem) {
            EmptyView()
        }

        CommandMenu("Account") {
            accountMenuItems
        }

        CommandGroup(replacing: .appTermination) {
            if showsMenuBarExtra {
                Button("Hide to Menu Bar") {
                    applicationDelegate.handlePrimaryQuitCommand()
                }
                .keyboardShortcut("q", modifiers: [.command])

                Divider()

                Button("Quit Codex Switcher") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: [.command, .option])
            } else {
                Button("Quit Codex Switcher") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: [.command])
            }
        }
    }

    @ViewBuilder
    private var accountMenuItems: some View {
        let accountIDs = controller.selectedAccountIDsForMenuActions

        if accountIDs.count > 1 {
            multipleAccountsMenuItems(accountIDs: accountIDs)
        } else {
            singleAccountMenuItems(accountIDs: accountIDs)
        }
    }

    @ViewBuilder
    private func singleAccountMenuItems(accountIDs: Set<UUID>) -> some View {
        Button {
            if let selectedAccountID = controller.selectedAccountID {
                openWindow(id: AccountDetailsWindowID.details, value: selectedAccountID)
            }
        } label: {
            menuActionLabel(title: "Get Info", systemImage: "info.circle")
        }
        .keyboardShortcut("i", modifiers: [.command])
        .disabled(controller.selectedAccountID == nil)

        Button {
            controller.copyAccountsToPasteboard(withIDs: accountIDs)
        } label: {
            menuActionLabel(title: "Copy", systemImage: "doc.on.doc")
        }
        .disabled(accountIDs.isEmpty)

        shareMenu(for: accountIDs)

        Divider()

        Button {
            controller.switchSelectedAccount()
        } label: {
            menuActionLabel(title: "Log In", systemImage: "arrow.right.circle")
        }
        .keyboardShortcut("l", modifiers: [.command])
        .disabled(controller.selectedAccountID == nil)

        Button {
            controller.beginRenamingSelectedAccount()
        } label: {
            menuActionLabel(title: "Rename", systemImage: "pencil")
        }
        .keyboardShortcut(.return, modifiers: [])
        .disabled(controller.selectedAccountID == nil)

        Menu {
            ForEach(AccountIconOption.displayOrder) { icon in
                Button {
                    controller.setSelectedAccountIcon(icon)
                } label: {
                    checkedMenuLabel(
                        title: icon.title,
                        systemImage: icon.systemName,
                        isSelected: controller.selectedAccountIconOption == icon
                    )
                }
            }
        } label: {
            menuActionLabel(title: "Choose Icon", systemImage: "square.grid.2x2")
        }
        .disabled(controller.selectedAccountID == nil)

        Button {
            controller.setSelectedAccountPinned(controller.selectedAccountIsPinned != true)
        } label: {
            menuActionLabel(
                title: controller.selectedAccountIsPinned == true ? "Unpin" : "Pin",
                systemImage: controller.selectedAccountIsPinned == true ? "pin.slash" : "pin"
            )
        }
        .keyboardShortcut("p", modifiers: [.command])
        .disabled(controller.selectedAccountID == nil)

        Divider()

        removeAccountsButton(accountIDs: accountIDs)
            .disabled(accountIDs.isEmpty)
    }

    @ViewBuilder
    private func multipleAccountsMenuItems(accountIDs: Set<UUID>) -> some View {
        Button {
            controller.copyAccountsToPasteboard(withIDs: accountIDs)
        } label: {
            menuActionLabel(title: "Copy", systemImage: "doc.on.doc")
        }
        .disabled(accountIDs.isEmpty)

        shareMenu(for: accountIDs)

        Divider()

        removeAccountsButton(accountIDs: accountIDs)
    }

    @ViewBuilder
    private func shareMenu(for accountIDs: Set<UUID>) -> some View {
        let sharingServices = accountIDs.isEmpty ? [] : controller.accountArchiveSharingServiceOptions()

        Menu {
            ForEach(sharingServices) { service in
                Button {
                    controller.shareAccounts(withIDs: accountIDs, using: service)
                } label: {
                    shareServiceLabel(service)
                }
            }
        } label: {
            menuActionLabel(title: "Share", systemImage: "square.and.arrow.up")
        }
        .disabled(accountIDs.isEmpty || sharingServices.isEmpty)
    }

    private func removeAccountsButton(accountIDs: Set<UUID>) -> some View {
        Button(role: .destructive) {
            controller.removeAccounts(withIDs: accountIDs)
        } label: {
            destructiveMenuLabel(title: "Remove", systemImage: "trash")
        }
    }

    private func shareServiceLabel(_ service: AccountArchiveSharingServiceOption) -> some View {
        Label {
            Text(service.title)
        } icon: {
            Image(nsImage: service.image)
        }
    }

    private func menuActionLabel(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
    }

    private func destructiveMenuLabel(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .foregroundStyle(.red)
    }

    @ViewBuilder
    private func checkedMenuLabel(title: String, systemImage: String? = nil, isSelected: Bool) -> some View {
        HStack {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }

            if isSelected {
                Spacer()
                Image(systemName: "checkmark")
            }
        }
    }
}
