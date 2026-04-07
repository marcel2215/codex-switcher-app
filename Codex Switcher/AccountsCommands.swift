//
//  AccountsCommands.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-07.
//

import SwiftUI

struct AccountsCommands: Commands {
    @ObservedObject var controller: AppController

    var body: some Commands {
        // Keep standard macOS categories intact, and only use a custom top-level
        // menu for actions that are truly account-specific.
        CommandGroup(after: .newItem) {
            Button("Add Current Account") {
                controller.captureCurrentAccount()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }

        CommandGroup(after: .pasteboard) {
            Divider()

            Button("Rename Account") {
                controller.beginRenamingSelectedAccount()
            }
            .keyboardShortcut(.return, modifiers: [])
            .disabled(controller.selection.count != 1)

            Menu("Choose Account Icon") {
                ForEach(AccountIconOption.allCases) { icon in
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

            Button(role: .destructive) {
                controller.removeSelectedAccounts()
            } label: {
                Label("Remove Account", systemImage: "trash")
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

            Divider()

            Button("Clear Search") {
                controller.searchText = ""
            }
            .disabled(controller.searchText.isEmpty)
        }

        CommandMenu("Account") {
            Button("Log In to Selected Account") {
                controller.switchSelectedAccount()
            }
            .disabled(controller.selection.count != 1)

            Button("Refresh Active Account") {
                controller.refreshActiveAccountIndicator(promptIfNeeded: false)
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
