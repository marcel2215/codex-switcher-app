//
//  ContentView.swift
//  Codex Switcher
//
//  Created by Marcel Kwiatkowski on 2026-04-06.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @ObservedObject var controller: AppController

    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoManager) private var undoManager
    @Query private var accounts: [StoredAccount]

    private var displayedAccounts: [StoredAccount] {
        controller.displayedAccounts(from: accounts)
    }

    private var undoManagerTaskID: ObjectIdentifier? {
        undoManager.map(ObjectIdentifier.init)
    }

    var body: some View {
        Group {
            if displayedAccounts.isEmpty {
                ContentUnavailableView(
                    controller.searchText.isEmpty ? "No Saved Accounts" : "No Matching Accounts",
                    systemImage: controller.searchText.isEmpty ? "person.crop.rectangle.stack" : "magnifyingglass",
                    description: Text(
                        controller.searchText.isEmpty
                            ? "Click the add button to capture the account currently stored in Codex."
                            : "Try a different search term."
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $controller.selection) {
                    ForEach(displayedAccounts) { account in
                        AccountRowView(
                            account: account,
                            isCurrentAccount: controller.activeIdentityKey == account.identityKey,
                            isSelected: controller.selection.contains(account.id),
                            isRenaming: controller.renameTargetID == account.id,
                            canReorder: controller.canEditCustomOrder,
                            onRemove: { controller.removeAccounts(withIDs: [account.id]) },
                            onCommitRename: { newName in
                                controller.commitRename(for: account.id, proposedName: newName)
                            },
                            onCancelRename: {
                                controller.cancelRename(for: account.id)
                            }
                        )
                        .tag(account.id)
                    }
                    .dropDestination(for: String.self) { items, index in
                        controller.reorderDraggedAccounts(
                            items,
                            to: index,
                            visibleAccounts: displayedAccounts
                        )
                    }
                }
                .background(
                    ListDoubleClickBridge(
                        rowIDs: displayedAccounts.map(\.id),
                        onDoubleClick: controller.login(accountID:)
                    )
                )
            }
        }
        .navigationTitle("Codex Switcher")
        .toolbar {
            ToolbarItemGroup {
                Button(action: controller.captureCurrentAccount) {
                    Label("Add Account", systemImage: "plus")
                }
                .help("Capture the currently active Codex account")

                Menu {
                    ForEach(AccountSortCriterion.allCases) { criterion in
                        Button {
                            controller.sortCriterion = criterion
                        } label: {
                            sortMenuLabel(
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
                            sortMenuLabel(
                                title: direction.menuTitle,
                                isSelected: controller.sortDirection == direction
                            )
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .help("Change the list sort order")
            }
        }
        .searchable(text: $controller.searchText)
        .contextMenu(forSelectionType: UUID.self) { selection in
            if selection.count == 1, let accountID = selection.first {
                Button("Log In") {
                    controller.login(accountID: accountID)
                }

                Button("Rename") {
                    controller.beginRenaming(accountID: accountID)
                }

                Menu("Choose Icon") {
                    if let selectedAccount = accounts.first(where: { $0.id == accountID }) {
                        ForEach(AccountIconOption.allCases) { icon in
                            Button {
                                controller.setIcon(icon, for: accountID)
                            } label: {
                                menuChoiceLabel(
                                    title: icon.title,
                                    systemImage: icon.systemName,
                                    isSelected: AccountIconOption.resolve(from: selectedAccount.iconSystemName) == icon
                                )
                            }
                        }
                    }
                }

                Divider()

                Button("Remove", role: .destructive) {
                    controller.removeAccounts(withIDs: selection)
                }
            } else if !selection.isEmpty {
                Button("Remove", role: .destructive) {
                    controller.removeAccounts(withIDs: selection)
                }
            }
        }
        .onDeleteCommand {
            controller.removeSelectedAccounts()
        }
        .onMoveCommand { direction in
            controller.moveSelection(direction: direction, visibleAccounts: displayedAccounts)
        }
        .onKeyPress(.delete) {
            guard !controller.selection.isEmpty else {
                return .ignored
            }
            controller.removeSelectedAccounts()
            return .handled
        }
        .onKeyPress(.return) {
            guard controller.selection.count == 1, controller.renameTargetID == nil else {
                return .ignored
            }
            controller.beginRenamingSelectedAccount()
            return .handled
        }
        .task {
            controller.configure(modelContext: modelContext, undoManager: undoManager)
            controller.refreshActiveAccountIndicator(promptIfNeeded: false)
        }
        .task(id: undoManagerTaskID) {
            controller.configure(modelContext: modelContext, undoManager: undoManager)
        }
        .alert(item: $controller.presentedAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    @ViewBuilder
    private func sortMenuLabel(title: String, isSelected: Bool) -> some View {
        HStack {
            Text(title)
            if isSelected {
                Spacer()
                Image(systemName: "checkmark")
            }
        }
    }

    @ViewBuilder
    private func menuChoiceLabel(title: String, systemImage: String, isSelected: Bool) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            if isSelected {
                Spacer()
                Image(systemName: "checkmark")
            }
        }
    }
}

#Preview {
    let controller = AppController(
        authFileManager: PreviewAuthFileManager(),
        notificationManager: PreviewNotificationManager()
    )

    ContentView(controller: controller)
        .modelContainer(PreviewData.makeContainer())
}
