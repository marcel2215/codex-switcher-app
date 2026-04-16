//
//  AccountsCommands.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-07.
//

import AppKit
import SwiftUI

struct AccountsCommands: Commands {
    let controller: AppController
    let applicationDelegate: ApplicationDelegate
    let showsMenuBarExtra: Bool

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

            Divider()

            Button("Import...") {
                controller.beginAccountArchiveImport()
            }
            .keyboardShortcut("i", modifiers: [.command])
        }

        CommandGroup(after: .pasteboard) {
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

        // This utility app does not print documents, so reuse the standard
        // Print slot for pinning to avoid conflicting with macOS' built-in Cmd-P.
        CommandGroup(replacing: .printItem) {
            Button(controller.selectedAccountIsPinned == true ? "Unpin" : "Pin") {
                controller.setSelectedAccountPinned(controller.selectedAccountIsPinned != true)
            }
            .keyboardShortcut("p", modifiers: [.command])
            .disabled(controller.selection.count != 1)
        }

        CommandMenu("Account") {
            Button("Log In") {
                controller.switchSelectedAccount()
            }
            .keyboardShortcut("l", modifiers: [.command])
            .disabled(controller.selection.count != 1)

            Divider()

            Button(controller.selectedAccountIsPinned == true ? "Unpin" : "Pin") {
                controller.setSelectedAccountPinned(controller.selectedAccountIsPinned != true)
            }
            .keyboardShortcut("p", modifiers: [.command])
            .disabled(controller.selection.count != 1)

            Button("Rename") {
                controller.beginRenamingSelectedAccount()
            }
            .keyboardShortcut(.return, modifiers: [])
            .disabled(controller.selection.count != 1)

            Menu("Choose Icon") {
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
            }
            .disabled(controller.selection.count != 1)

            Divider()

            Button("Export...") {
                controller.beginExportSelectedAccount()
            }
            .disabled(controller.selection.count != 1)
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
