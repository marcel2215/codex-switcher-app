//
//  ContentView.swift
//  Codex Switcher Mac App
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
    @FocusState private var focusedRenameAccountID: UUID?
    @State private var accountListItems: [AccountListItem] = []
    @State private var iconPickerAccountID: UUID?
    @State private var pendingCustomOrderIDs: [UUID]?
    // Keep move gestures handle-scoped in custom mode so the rest of the row
    // can remain a pure export drag source for Finder and other apps.
    @State private var hoveredReorderHandleID: UUID?

    private var displayedAccounts: [StoredAccount] {
        controller.displayedAccounts(from: accounts)
    }

    private var displayedAccountListItems: [AccountListItem] {
        let noneItem = AccountListItem.none(isCurrentAccount: controller.activeIdentityKey == nil)
        return [noneItem] + displayedAccounts.map { account in
            AccountListItem(
                account: account,
                isCurrentAccount: controller.activeIdentityKey == account.identityKey
            )
        }
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

    private var emptyAccountsTitle: String {
        controller.searchText.isEmpty ? "No Accounts" : "No Results"
    }

    private var emptyAccountsSystemImage: String {
        controller.searchText.isEmpty ? "person.crop.rectangle.stack" : "magnifyingglass"
    }

    private var emptyAccountsDescription: String {
        if !controller.searchText.isEmpty {
            return "Try a different search term."
        }

        return controller.canCaptureCurrentAccount
            ? "Click the plus button to add the currently used account."
            : controller.captureCurrentAccountHelpText
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

            if let banner = controller.pendingCodexRestartBanner {
                pendingRestartBanner(banner)
                    .padding(.horizontal, 16)
                    .padding(.top, controller.shouldShowAuthStatusBanner ? 0 : 16)
                    .padding(.bottom, 8)
            }

            Group {
                if displayedAccountListItems.isEmpty {
                    emptyAccountsView
                } else {
                    accountList
                }
            }
        }
        .background(
            MouseButtonMonitorBridge {
                clearReorderHandleInteraction()
            }
        )
        .navigationTitle("Codex Switcher")
        .toolbar {
            ToolbarItemGroup {
                Button(action: controller.captureCurrentAccount) {
                    Label("Add Account", systemImage: "plus")
                }
                .disabled(!controller.canCaptureCurrentAccount)
                .help(controller.captureCurrentAccountHelpText)

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
            syncAccountListItems(with: displayedAccountListItems)
        }
        .task(id: undoManagerTaskID) {
            controller.configure(modelContext: modelContext, undoManager: undoManager)
        }
        .onAppear {
            syncAccountListItems(with: displayedAccountListItems)
        }
        .onChange(of: displayedAccountListItems) { _, newItems in
            syncAccountListItems(with: newItems)
        }
        .onChange(of: accountListItems.map(\.id)) { _, reorderedIDs in
            persistVisibleAccountOrderIfNeeded(reorderedIDs)
        }
        .onChange(of: controller.canEditCustomOrder) { _, canEditCustomOrder in
            if !canEditCustomOrder {
                pendingCustomOrderIDs = nil
                clearReorderHandleInteraction()
            }
            syncAccountListItems(with: displayedAccountListItems)
        }
        .onChange(of: controller.renameTargetID) { _, newValue in
            if newValue != nil {
                clearReorderHandleInteraction()
            }
            handleRenameTargetChange(newValue)
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
        .alert(item: $controller.unavailableAccountRecoveryPrompt) { prompt in
            Alert(
                title: Text("Account Unavailable"),
                message: Text(unavailableAccountMessage(for: prompt)),
                primaryButton: .destructive(Text("Remove Account")) {
                    controller.removeUnavailableAccountFromPrompt(prompt)
                },
                secondaryButton: .cancel(Text("Keep")) {
                    controller.keepUnavailableAccountFromPrompt()
                }
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
                    .accessibilityLabel(controller.authAccessState.message)
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("auth-status-banner")
    }

    private var emptyAccountsView: some View {
        ContentUnavailableView(
            emptyAccountsTitle,
            systemImage: emptyAccountsSystemImage,
            description: Text(emptyAccountsDescription)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func pendingRestartBanner(_ banner: PendingCodexRestartBanner) -> some View {
        GroupBox {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Account change pending")
                        .font(.headline)
                    Text("Close and reopen Codex to use \(banner.target.displayName).")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Button {
                    controller.dismissPendingCodexRestartBanner()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func unavailableAccountMessage(for prompt: UnavailableAccountRecoveryPrompt) -> String {
        """
        The saved Codex auth snapshot for "\(prompt.accountName)" is no longer accepted. It may have expired, been revoked, or been invalidated by a Codex logout.

        Do not use the Log out button in the Codex app to fix this. Codex logout can revoke managed ChatGPT tokens. To use this account again, keep it here, select None to locally clear auth.json, sign in again, then press + to capture a fresh snapshot.

        Would you like to remove this account from Codex Switcher or keep it?
        """
    }

    @ViewBuilder
    private var accountList: some View {
        if controller.canEditCustomOrder {
            List(
                $accountListItems,
                editActions: [.move],
                selection: $controller.selection
            ) { $item in
                accountListEntry(for: item, draftName: $item.name)
            }
            .contextMenu(forSelectionType: UUID.self) { targetIDs in
                accountContextMenu(forSelectionIDs: targetIDs)
            } primaryAction: { targetIDs in
                handlePrimaryAction(forSelectionIDs: targetIDs)
            }
        } else {
            List($accountListItems, selection: $controller.selection) { $item in
                accountListEntry(for: item, draftName: $item.name)
            }
            .contextMenu(forSelectionType: UUID.self) { targetIDs in
                accountContextMenu(forSelectionIDs: targetIDs)
            } primaryAction: { targetIDs in
                handlePrimaryAction(forSelectionIDs: targetIDs)
            }
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

    private func shouldRemoveSelection(for keyPress: KeyPress) -> Bool {
        Self.supportsRemovalShortcut(modifiers: keyPress.modifiers)
    }

    private func accountListRow(for item: AccountListItem, draftName: Binding<String>) -> some View {
        HStack(alignment: .center, spacing: 8) {
            if controller.canEditCustomOrder {
                reorderHandle(for: item.id, isEnabled: !item.isNone)
            }

            Image(systemName: item.iconSystemName)
                .font(.title3)
                .frame(width: 20, alignment: .center)
                .foregroundStyle(.secondary)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 2) {
                if !item.isNone, controller.renameTargetID == item.id {
                    TextField("", text: draftName)
                        .textFieldStyle(.plain)
                        .focused($focusedRenameAccountID, equals: item.id)
                        .onSubmit {
                            controller.commitRename(for: item.id, proposedName: draftName.wrappedValue)
                        }
                        .onChange(of: focusedRenameAccountID) { _, focusedID in
                            guard controller.renameTargetID == item.id, focusedID != item.id else {
                                return
                            }

                            controller.commitRename(for: item.id, proposedName: draftName.wrappedValue)
                        }
                        .onAppear {
                            focusedRenameAccountID = item.id
                        }
                        .onKeyPress(.escape) {
                            controller.cancelRename(for: item.id)
                            return .handled
                        }
                } else {
                    Text(item.displayName)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .allowsHitTesting(false)
                }

                AccountMetadataText(
                    lastLoginAt: item.lastLoginAt,
                    sevenDayLimitUsedPercent: item.sevenDayLimitUsedPercent,
                    fiveHourLimitUsedPercent: item.fiveHourLimitUsedPercent,
                    sevenDayResetsAt: item.sevenDayResetsAt,
                    fiveHourResetsAt: item.fiveHourResetsAt,
                    font: .subheadline
                )
                .allowsHitTesting(false)
            }

            Spacer(minLength: 0)

            trailingStatusIcon(for: item)
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Keep the row itself presentation-only so the enclosing native list
        // owns selection, double-click primary action, and row dragging.
        .contentShape(Rectangle())
    }

    private func accountListEntry(for item: AccountListItem, draftName: Binding<String>) -> some View {
        accountListRow(for: item, draftName: draftName)
            .moveDisabled(item.isNone || (controller.canEditCustomOrder && !isReorderInteractionArmed))
            .onAppear {
                if !item.isNone {
                    handleRateLimitVisibility(true, for: item.id)
                }
            }
            .onDisappear {
                clearReorderHandleInteractionIfNeeded(for: item.id)
                if !item.isNone {
                    handleRateLimitVisibility(false, for: item.id)
                }
            }
            .itemProvider {
                accountListDragItemProvider(forDraggedRowID: item.id)
            }
    }

    private func trailingStatusIcon(for item: AccountListItem) -> some View {
        Group {
            if item.isUnavailable {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("This saved Codex account is unavailable.")
                    .accessibilityLabel("Unavailable")
            } else if item.isCurrentAccount {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(controller.selection.contains(item.id) ? Color.white : Color.accentColor)
                    .help(item.isNone ? "Codex is locally logged out" : "Currently active in Codex")
                    .accessibilityLabel("Current")
            } else {
                Color.clear
                    .accessibilityHidden(true)
            }
        }
        .frame(width: 16, height: 16)
        .allowsHitTesting(false)
    }

    private func handlePrimaryAction(forSelectionIDs targetIDs: Set<UUID>) {
        guard
            controller.renameTargetID == nil,
            targetIDs.count == 1,
            let accountID = targetIDs.first
        else {
            return
        }

        controller.selection = targetIDs
        controller.login(accountID: accountID)
    }

    private func handleRenameTargetChange(_ newValue: UUID?) {
        focusedRenameAccountID = newValue

        if newValue == nil {
            syncAccountListItems(with: displayedAccountListItems)
        }
    }

    private func handleRateLimitVisibility(_ isVisible: Bool, for accountID: UUID) {
        guard let identityKey = displayedAccounts.first(where: { $0.id == accountID })?.identityKey else {
            return
        }

        controller.setRateLimitVisibility(isVisible, for: identityKey)
    }

    private func reorderHandle(for rowID: UUID, isEnabled: Bool = true) -> some View {
        Image(systemName: "line.3.horizontal")
            .font(.callout.weight(.semibold))
            .foregroundStyle(isEnabled && isReorderHandleHovered(for: rowID) ? .primary : .tertiary)
            .frame(width: 18, alignment: .center)
            .padding(.trailing, 2)
            .contentShape(Rectangle())
            .help(isEnabled ? "Drag to reorder" : "This row cannot be reordered")
            .accessibilityHidden(true)
            .allowsHitTesting(isEnabled)
            .onHover { hovering in
                guard isEnabled else {
                    return
                }

                guard !isPrimaryMouseButtonPressed else {
                    return
                }

                if hovering {
                    hoveredReorderHandleID = rowID
                } else if hoveredReorderHandleID == rowID {
                    hoveredReorderHandleID = nil
                }
            }
    }

    private func isReorderHandleHovered(for rowID: UUID) -> Bool {
        hoveredReorderHandleID == rowID
    }

    private var isReorderInteractionArmed: Bool {
        controller.canEditCustomOrder
            && hoveredReorderHandleID != nil
            && controller.renameTargetID == nil
    }

    private func clearReorderHandleInteraction() {
        hoveredReorderHandleID = nil
    }

    private func clearReorderHandleInteractionIfNeeded(for rowID: UUID) {
        if hoveredReorderHandleID == rowID {
            hoveredReorderHandleID = nil
        }
    }

    private var isPrimaryMouseButtonPressed: Bool {
        (NSEvent.pressedMouseButtons & 0x1) != 0
    }

    private func accountListDragItemProvider(forDraggedRowID rowID: UUID) -> NSItemProvider? {
        guard controller.renameTargetID == nil else {
            return nil
        }

        // The handle is reserved for in-list moves; only the row body should
        // vend the external archive payload.
        if controller.canEditCustomOrder && isReorderHandleHovered(for: rowID) {
            return nil
        }

        let draggedAccounts = dragAccounts(forDraggedRowID: rowID)
        guard !draggedAccounts.isEmpty else {
            return nil
        }

        return controller.macOSDragItemProvider(
            for: draggedAccounts,
            includeReorderToken: false
        )
    }

    private func dragAccounts(forDraggedRowID rowID: UUID) -> [StoredAccount] {
        // Match native macOS list behavior: dragging a selected row exports the
        // current ordered selection, while dragging an unselected row leaves
        // the existing selection alone and scopes the drag to that row only.
        if controller.selection.contains(rowID) {
            let selectedIDs = controller.selection
            let orderedSelection = displayedAccounts.filter { selectedIDs.contains($0.id) }
            if !orderedSelection.isEmpty {
                return orderedSelection
            }
        }

        guard let draggedAccount = displayedAccounts.first(where: { $0.id == rowID }) else {
            return []
        }

        return [draggedAccount]
    }

    private func syncAccountListItems(with sourceItems: [AccountListItem]) {
        let sourceIDs = sourceItems.map(\.id)

        if pendingCustomOrderIDs == sourceIDs {
            pendingCustomOrderIDs = nil
        }

        let currentItemsByID = Dictionary(uniqueKeysWithValues: accountListItems.map { ($0.id, $0) })
        let mergedSourceItems = sourceItems.map { sourceItem in
            guard
                controller.renameTargetID == sourceItem.id,
                let currentItem = currentItemsByID[sourceItem.id]
            else {
                return sourceItem
            }

            var mergedItem = sourceItem
            mergedItem.name = currentItem.name
            return mergedItem
        }

        let targetOrderIDs: [UUID]
        if let pendingCustomOrderIDs,
           controller.canEditCustomOrder,
           pendingCustomOrderIDs.count == sourceIDs.count,
           Set(pendingCustomOrderIDs) == Set(sourceIDs),
           pendingCustomOrderIDs != sourceIDs {
            // Keep the user-visible order stable while SwiftData catches up to
            // a just-finished native move operation.
            targetOrderIDs = pendingCustomOrderIDs
        } else {
            targetOrderIDs = sourceIDs
        }

        let mergedItemsByID = Dictionary(uniqueKeysWithValues: mergedSourceItems.map { ($0.id, $0) })
        let orderedItems = targetOrderIDs.compactMap { mergedItemsByID[$0] }
        let resolvedItems = orderedItems.count == mergedSourceItems.count ? orderedItems : mergedSourceItems

        guard resolvedItems != accountListItems else {
            return
        }

        accountListItems = resolvedItems
    }

    private func persistVisibleAccountOrderIfNeeded(_ reorderedIDs: [UUID]) {
        guard controller.canEditCustomOrder else {
            pendingCustomOrderIDs = nil
            clearReorderHandleInteraction()
            return
        }

        let visibleIDs = displayedAccountListItems.filter { !$0.isNone }.map(\.id)
        let reorderedAccountIDs = reorderedIDs.filter { $0 != AppController.noneAccountSelectionID }
        guard
            reorderedAccountIDs.count == visibleIDs.count,
            Set(reorderedAccountIDs) == Set(visibleIDs)
        else {
            return
        }

        guard reorderedAccountIDs != visibleIDs else {
            if pendingCustomOrderIDs == reorderedAccountIDs {
                pendingCustomOrderIDs = nil
            }
            return
        }

        pendingCustomOrderIDs = [AppController.noneAccountSelectionID] + reorderedAccountIDs
        clearReorderHandleInteraction()
        controller.persistCustomOrder(for: reorderedAccountIDs, visibleAccounts: displayedAccounts)
    }

    @ViewBuilder
    private func accountContextMenu(forSelectionIDs targetIDs: Set<UUID>) -> some View {
        if targetIDs.isEmpty {
            Button {
                controller.captureCurrentAccount()
            } label: {
                menuActionLabel(title: "Add Account", systemImage: "plus")
            }

            Button {
                controller.beginAccountArchiveImport()
            } label: {
                menuActionLabel(title: "Import Archive", systemImage: "square.and.arrow.down")
            }
        } else if targetIDs.contains(AppController.noneAccountSelectionID) {
            EmptyView()
        } else if targetIDs.count == 1,
                  let accountID = targetIDs.first,
                  let account = accounts.first(where: { $0.id == accountID }) {
            singleAccountContextMenu(for: account, targetIDs: targetIDs)
        } else {
            removeAccountsButton(targetIDs: targetIDs)
        }
    }

    @ViewBuilder
    private func singleAccountContextMenu(for account: StoredAccount, targetIDs: Set<UUID>) -> some View {
        Button {
            controller.selection = targetIDs
            controller.login(accountID: account.id)
        } label: {
            menuActionLabel(title: "Log In", systemImage: "arrow.right.circle")
        }

        Button {
            controller.selection = targetIDs
            controller.setPinned(!account.isPinned, for: account.id)
        } label: {
            menuActionLabel(
                title: account.isPinned ? "Unpin" : "Pin",
                systemImage: account.isPinned ? "pin.slash" : "pin"
            )
        }

        Button {
            controller.selection = targetIDs
            controller.beginRenaming(accountID: account.id)
        } label: {
            menuActionLabel(title: "Rename", systemImage: "pencil")
        }

        Button {
            controller.selection = targetIDs
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

private struct AccountListItem: Identifiable, Hashable {
    let id: UUID
    let isNone: Bool
    var name: String
    let displayName: String
    let iconSystemName: String
    let lastLoginAt: Date?
    let sevenDayLimitUsedPercent: Int?
    let fiveHourLimitUsedPercent: Int?
    let sevenDayResetsAt: Date?
    let fiveHourResetsAt: Date?
    let isCurrentAccount: Bool
    let isUnavailable: Bool

    init(account: StoredAccount, isCurrentAccount: Bool) {
        id = account.id
        isNone = false
        name = account.name
        let resolvedName = AccountsPresentationLogic.displayName(for: account)
        displayName = account.isUnavailable ? "\(resolvedName) (Unavailable)" : resolvedName
        iconSystemName = AccountIconOption.resolve(from: account.iconSystemName).systemName
        lastLoginAt = account.lastLoginAt
        sevenDayLimitUsedPercent = account.isUnavailable ? 0 : account.sevenDayLimitUsedPercent
        fiveHourLimitUsedPercent = account.isUnavailable ? 0 : account.fiveHourLimitUsedPercent
        sevenDayResetsAt = account.isUnavailable ? nil : account.sevenDayResetsAt
        fiveHourResetsAt = account.isUnavailable ? nil : account.fiveHourResetsAt
        self.isCurrentAccount = isCurrentAccount
        isUnavailable = account.isUnavailable
    }

    static func none(isCurrentAccount: Bool) -> AccountListItem {
        AccountListItem(
            id: AppController.noneAccountSelectionID,
            isNone: true,
            name: "None",
            displayName: "None",
            iconSystemName: "power",
            lastLoginAt: nil,
            sevenDayLimitUsedPercent: 0,
            fiveHourLimitUsedPercent: 0,
            sevenDayResetsAt: nil,
            fiveHourResetsAt: nil,
            isCurrentAccount: isCurrentAccount,
            isUnavailable: false
        )
    }

    private init(
        id: UUID,
        isNone: Bool,
        name: String,
        displayName: String,
        iconSystemName: String,
        lastLoginAt: Date?,
        sevenDayLimitUsedPercent: Int?,
        fiveHourLimitUsedPercent: Int?,
        sevenDayResetsAt: Date?,
        fiveHourResetsAt: Date?,
        isCurrentAccount: Bool,
        isUnavailable: Bool
    ) {
        self.id = id
        self.isNone = isNone
        self.name = name
        self.displayName = displayName
        self.iconSystemName = iconSystemName
        self.lastLoginAt = lastLoginAt
        self.sevenDayLimitUsedPercent = sevenDayLimitUsedPercent
        self.fiveHourLimitUsedPercent = fiveHourLimitUsedPercent
        self.sevenDayResetsAt = sevenDayResetsAt
        self.fiveHourResetsAt = fiveHourResetsAt
        self.isCurrentAccount = isCurrentAccount
        self.isUnavailable = isUnavailable
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
