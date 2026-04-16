//
//  ContentView.swift
//  Codex Switcher
//
//  Created by Marcel Kwiatkowski on 2026-04-06.
//

import AppKit
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var controller: AppController

    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoManager) private var undoManager
    @Query private var accounts: [StoredAccount]
    @State private var iconPickerAccountID: UUID?

    private var displayedAccounts: [StoredAccount] {
        controller.displayedAccounts(from: accounts)
    }

    private var undoManagerTaskID: ObjectIdentifier? {
        undoManager.map(ObjectIdentifier.init)
    }

    private var iconPickerAccount: StoredAccount? {
        guard let iconPickerAccountID else {
            return nil
        }

        return accounts.first(where: { $0.id == iconPickerAccountID })
    }

    private var isShowingIconPicker: Binding<Bool> {
        Binding(
            get: { iconPickerAccount != nil },
            set: { isPresented in
                if !isPresented {
                    iconPickerAccountID = nil
                }
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if controller.shouldShowAuthStatusBanner {
                authStatusBanner
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
            }

            Group {
                if displayedAccounts.isEmpty {
                    ContentUnavailableView(
                        controller.searchText.isEmpty ? "No Accounts" : "No Results",
                        systemImage: controller.searchText.isEmpty ? "person.crop.rectangle.stack" : "magnifyingglass",
                        description: Text(
                            controller.searchText.isEmpty
                                ? "Click the plus button to add the currently used account."
                                : "Try a different search term."
                        )
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(selection: $controller.selection) {
                        ForEach(displayedAccounts) { account in
                            accountListRow(for: account)
                        }
                        .dropDestination(for: String.self) { items, index in
                            controller.reorderDraggedAccounts(
                                items,
                                to: index,
                                visibleAccounts: displayedAccounts
                            )
                        }
                    }
                }
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

                    if controller.sortCriterion != .custom {
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
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .help("Change the list sort order")
            }
        }
        .searchable(text: $controller.searchText)
        .fileImporter(
            isPresented: $controller.isShowingLocationPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false,
            onCompletion: controller.handleLocationImport
        )
        .fileImporter(
            isPresented: $controller.isShowingAccountArchiveImporter,
            allowedContentTypes: UTType.openableCodexAccountArchiveTypes,
            onCompletion: controller.handleAccountArchiveImport
        )
        .fileDialogCustomizationID("codex-auth-location")
        .fileDialogDefaultDirectory(FileManager.default.homeDirectoryForCurrentUser)
        .fileDialogBrowserOptions([.includeHiddenFiles])
        .onOpenURL(perform: controller.handleIncomingAccountArchiveURL)
        .dropDestination(for: URL.self, isEnabled: true) { items, _ in
            controller.handleDroppedAccountArchiveURLs(items)
        }
        .onMoveCommand { direction in
            controller.moveSelection(direction: direction, visibleAccounts: displayedAccounts)
        }
        .onKeyPress(.delete, phases: [.down]) { keyPress in
            guard
                !controller.selection.isEmpty,
                controller.renameTargetID == nil,
                shouldRemoveSelection(for: keyPress)
            else {
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
        .onKeyPress(.space, phases: [.down]) { _ in
            guard Self.canSwitchSelectedAccountViaSpace(
                selectionCount: controller.selection.count,
                isRenaming: controller.renameTargetID != nil
            ) else {
                return .ignored
            }

            controller.switchSelectedAccount()
            return .handled
        }
        .task {
            controller.configure(modelContext: modelContext, undoManager: undoManager)
            controller.setApplicationActive(NSApplication.shared.isActive)
        }
        .task(id: undoManagerTaskID) {
            controller.configure(modelContext: modelContext, undoManager: undoManager)
        }
        .onAppear {
            controller.setPrimarySelectionContextPresented(true)
        }
        .onDisappear {
            controller.setPrimarySelectionContextPresented(false)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            controller.setApplicationActive(true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            controller.setApplicationActive(false)
        }
        .sheet(isPresented: isShowingIconPicker) {
            if let iconPickerAccount {
                AccountIconPickerView(
                    selectedIcon: AccountIconOption.resolve(from: iconPickerAccount.iconSystemName),
                    onSelect: { icon in
                        controller.setIcon(icon, for: iconPickerAccount.id)
                        iconPickerAccountID = nil
                    },
                    onCancel: {
                        iconPickerAccountID = nil
                    }
                )
            }
        }
        .alert(item: $controller.presentedAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var authStatusBanner: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Label(controller.authAccessState.title, systemImage: controller.authAccessState.systemImage)
                    .font(.headline)
                    .accessibilityIdentifier("auth-status-title")

                Text(controller.authAccessState.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("auth-status-message")

                HStack(spacing: 12) {
                    Button(controller.linkButtonTitle) {
                        controller.beginLinkingCodexLocation()
                    }
                    .accessibilityIdentifier("auth-link-button")

                    if controller.authAccessState != .unlinked {
                        Button("Refresh") {
                            controller.refresh()
                        }
                        .accessibilityIdentifier("auth-refresh-button")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("auth-status-banner")
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

    private func shouldRemoveSelection(for keyPress: KeyPress) -> Bool {
        Self.supportsRemovalShortcut(modifiers: keyPress.modifiers)
    }

    private func accountListRow(for account: StoredAccount) -> some View {
        AccountRowView(
            account: account,
            isCurrentAccount: controller.activeIdentityKey == account.identityKey,
            isSelected: controller.selection.contains(account.id),
            isRenaming: controller.renameTargetID == account.id,
            canReorder: controller.canEditCustomOrder,
            exportTransferItem: controller.archiveTransferItem(for: account),
            onRemove: { controller.removeAccounts(withIDs: [account.id]) },
            onSelect: { controller.selection = [account.id] },
            onDoubleClick: {
                controller.selection = [account.id]
                controller.login(accountID: account.id)
            },
            onCommitRename: { newName in
                controller.commitRename(for: account.id, proposedName: newName)
            },
            onCancelRename: {
                controller.cancelRename(for: account.id)
            }
        )
        .contextMenu { accountContextMenu(for: account) }
        .tag(account.id)
        .onAppear {
            controller.setRateLimitVisibility(true, for: account.identityKey)
        }
        .onDisappear {
            controller.setRateLimitVisibility(false, for: account.identityKey)
        }
    }

    private func contextMenuTargetIDs(for accountID: UUID) -> Set<UUID> {
        Self.contextMenuTargetIDs(
            clickedAccountID: accountID,
            currentSelection: controller.selection
        )
    }

    @ViewBuilder
    private func accountContextMenu(for account: StoredAccount) -> some View {
        let targetIDs = contextMenuTargetIDs(for: account.id)

        if targetIDs.count == 1 {
            singleAccountContextMenu(for: account, targetIDs: targetIDs)
        } else {
            removeAccountsButton(targetIDs: targetIDs)
        }
    }

    @ViewBuilder
    private func singleAccountContextMenu(for account: StoredAccount, targetIDs: Set<UUID>) -> some View {
        Button {
            controller.selection = [account.id]
            controller.login(accountID: account.id)
        } label: {
            menuActionLabel(title: "Log In", systemImage: "arrow.right.circle")
        }

        Button {
            controller.selection = [account.id]
            controller.setPinned(!account.isPinned, for: account.id)
        } label: {
            menuActionLabel(
                title: account.isPinned ? "Unpin" : "Pin",
                systemImage: account.isPinned ? "pin.slash" : "pin"
            )
        }

        Button {
            controller.beginRenaming(accountID: account.id)
        } label: {
            menuActionLabel(title: "Rename", systemImage: "pencil")
        }

        Button {
            controller.selection = [account.id]
            iconPickerAccountID = account.id
        } label: {
            menuActionLabel(title: "Choose Icon", systemImage: "square.grid.2x2")
        }

        Divider()

        removeAccountsButton(targetIDs: targetIDs)
    }

    private func removeAccountsButton(targetIDs: Set<UUID>) -> some View {
        Button(role: .destructive) {
            controller.removeAccounts(withIDs: targetIDs)
        } label: {
            destructiveMenuLabel(title: "Remove", systemImage: "trash")
        }
    }

    private func menuActionLabel(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
    }

    private func destructiveMenuLabel(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .foregroundStyle(.red)
    }
}

extension ContentView {
    /// Matches the delete-key combinations this list treats as an account
    /// removal shortcut. Keep this narrow so regular text editing shortcuts
    /// continue to work when inline rename is active.
    static func supportsRemovalShortcut(modifiers: EventModifiers) -> Bool {
        switch modifiers {
        case []:
            true
        case [.command]:
            true
        case [.shift]:
            true
        case [.command, .shift]:
            true
        default:
            false
        }
    }

    /// Right-click actions should target the clicked row unless that row is
    /// already part of the current multi-selection, in which case the menu
    /// applies to the selected rows together.
    static func contextMenuTargetIDs(clickedAccountID: UUID, currentSelection: Set<UUID>) -> Set<UUID> {
        if currentSelection.count > 1, currentSelection.contains(clickedAccountID) {
            currentSelection
        } else {
            [clickedAccountID]
        }
    }

    /// Space should behave like a lightweight "activate" action only when the
    /// list has exactly one selected account and inline rename is not active.
    static func canSwitchSelectedAccountViaSpace(selectionCount: Int, isRenaming: Bool) -> Bool {
        selectionCount == 1 && !isRenaming
    }
}

#Preview {
    let controller = AppController(
        authFileManager: PreviewAuthFileManager(),
        secretStore: PreviewSecretStore(),
        notificationManager: PreviewNotificationManager()
    )

    ContentView(controller: controller)
        .modelContainer(PreviewData.makeContainer())
}
