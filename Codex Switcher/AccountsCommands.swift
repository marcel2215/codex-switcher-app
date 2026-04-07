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
        CommandMenu("Accounts") {
            Button("Add Current Account") {
                controller.captureCurrentAccount()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("Log In") {
                controller.switchSelectedAccount()
            }
            .disabled(controller.selection.count != 1)

            Button("Rename") {
                controller.beginRenamingSelectedAccount()
            }
            .disabled(controller.selection.count != 1)

            Button("Remove") {
                controller.removeSelectedAccounts()
            }
            .disabled(controller.selection.isEmpty)

            Divider()

            ForEach(AccountSortCriterion.allCases) { criterion in
                Button {
                    controller.sortCriterion = criterion
                } label: {
                    menuLabel(
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
                    menuLabel(
                        title: direction.menuTitle,
                        isSelected: controller.sortDirection == direction
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func menuLabel(title: String, isSelected: Bool) -> some View {
        HStack {
            Text(title)
            if isSelected {
                Spacer()
                Image(systemName: "checkmark")
            }
        }
    }
}
