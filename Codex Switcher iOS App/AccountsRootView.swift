//
//  AccountsRootView.swift
//  Codex Switcher iOS App
//
//  Created by Codex on 2026-04-11.
//

import Observation
import OSLog
import SwiftData
import SwiftUI

struct AccountsRootView: View {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "CodexSwitcher",
        category: "AccountsRootView"
    )

    private enum ActiveAlert: Identifiable {
        case error(PresentedError)
        case removal(StoredAccount)

        var id: String {
            switch self {
            case .error(let error):
                return "error-\(error.id.uuidString)"
            case .removal(let account):
                return "removal-\(account.id.uuidString)"
            }
        }
    }

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var accounts: [StoredAccount]

    @Bindable private var quickActions: IOSHomeScreenQuickActionCoordinator
    @State private var controller = IOSAccountsController()
    @State private var rateLimitRefreshController = IOSRateLimitRefreshController()
    @State private var editMode: EditMode = .inactive
    // The compact stack can push both account IDs and nested detail routes,
    // so it needs a heterogeneous path instead of a typed `[UUID]`.
    @State private var compactNavigationPath = NavigationPath()
    @State private var selectedAccountID: UUID?
    @State private var selectedAccountIDsForEditing: Set<UUID> = []
    @State private var pendingSpotlightAccountIdentityKey: String?
    @State private var showingSettings = false
    @State private var accountPendingDeletion: StoredAccount?
    @State private var sortPreferences = CloudSortPreferences()

    init(quickActions: IOSHomeScreenQuickActionCoordinator = .shared) {
        self.quickActions = quickActions
    }

    static func shouldReturnToAccountsHome(
        afterRemovingAccountWithID accountID: UUID,
        usesCompactNavigation: Bool,
        selectedAccountID: UUID?
    ) -> Bool {
        usesCompactNavigation || selectedAccountID == accountID
    }

    private var displayedAccounts: [StoredAccount] {
        controller.displayedAccounts(from: accounts)
    }

    private var selectedAccount: StoredAccount? {
        accounts.first(where: { $0.id == selectedAccountID })
    }

    private var usesCompactNavigation: Bool {
        horizontalSizeClass == .compact
    }

    private var isEditing: Bool {
        editMode == .active
    }

    private var widgetSnapshotFingerprint: Int {
        WidgetSnapshotPublisher.fingerprint(for: accounts)
    }

    private var quickActionFingerprint: String {
        "\(widgetSnapshotFingerprint)|\(controller.sortCriterion.rawValue)|\(controller.sortDirection.rawValue)"
    }

    private var activeAlert: Binding<ActiveAlert?> {
        Binding(
            get: {
                if let error = controller.presentedError {
                    return .error(error)
                }

                if let accountPendingDeletion {
                    return .removal(accountPendingDeletion)
                }

                return nil
            },
            set: { newValue in
                switch newValue {
                case .none:
                    controller.presentedError = nil
                    accountPendingDeletion = nil
                case .error(let error):
                    controller.presentedError = error
                    accountPendingDeletion = nil
                case .removal(let account):
                    accountPendingDeletion = account
                    controller.presentedError = nil
                }
            }
        )
    }

    var body: some View {
        let searchTextBinding = Binding(
            get: { controller.searchText },
            set: { controller.searchText = $0 }
        )
        let rootContent = usesCompactNavigation
            ? AnyView(compactRootView(searchText: searchTextBinding))
            : AnyView(regularRootView(searchText: searchTextBinding))

        configuredRootContent(rootContent)
    }

    private func compactRootView(searchText: Binding<String>) -> some View {
        AnyView(
            NavigationStack(path: $compactNavigationPath) {
                compactAccountsList
                    .navigationTitle("Accounts")
                    .navigationDestination(for: UUID.self, destination: compactAccountDestination)
                    .searchable(text: searchText, prompt: "Search")
                    .toolbar(content: rootToolbar)
            }
        )
    }

    private func regularRootView(searchText: Binding<String>) -> some View {
        AnyView(
            NavigationSplitView {
                regularAccountsList
                    .navigationTitle("Accounts")
                    .searchable(text: searchText, prompt: "Search")
                    .toolbar(content: rootToolbar)
            } detail: {
                if let selectedAccount {
                    accountDetailView(for: selectedAccount)
                } else {
                    ContentUnavailableView(
                        "Select an Account",
                        systemImage: "person.crop.circle",
                        description: Text("Choose an account to view and edit its details.")
                    )
                }
            }
        )
    }

    private func configuredRootContent(_ rootContent: AnyView) -> some View {
        let notificationSettingsPublisher = NotificationCenter.default.publisher(
            for: CodexInAppNotificationSettingsSignal.didRequestOpenNotificationSettings
        )
        let baseContent =
            rootContent
            .environment(\.editMode, $editMode)
            .task {
                handleInitialLoad()
            }
            .onOpenURL(perform: handleIncomingArchiveURL)
            .dropDestination(for: URL.self, isEnabled: true) { items, _ in
                handleDroppedArchiveURLs(items)
            }
            .onReceive(notificationSettingsPublisher) { _ in
                openNotificationSettingsIfRequested()
            }
        let preferenceObservedContent =
            baseContent
            .onChange(of: controller.sortCriterion) { _, newValue in
                sortPreferences.persist(
                    sortCriterionRawValue: newValue.rawValue,
                    sortDirectionRawValue: controller.sortDirection.rawValue
                )
            }
            .onChange(of: controller.sortDirection) { _, newValue in
                sortPreferences.persist(
                    sortCriterionRawValue: controller.sortCriterion.rawValue,
                    sortDirectionRawValue: newValue.rawValue
                )
            }
            .onChange(of: sortPreferences.sortCriterionRawValue) { _, newValue in
                controller.restoreSortPreferences(
                    sortCriterionRawValue: newValue,
                    sortDirectionRawValue: sortPreferences.sortDirectionRawValue
                )
            }
            .onChange(of: sortPreferences.sortDirectionRawValue) { _, newValue in
                controller.restoreSortPreferences(
                    sortCriterionRawValue: sortPreferences.sortCriterionRawValue,
                    sortDirectionRawValue: newValue
                )
            }
        let interactionObservedContent =
            preferenceObservedContent
            .onChange(of: usesCompactNavigation) { _, isCompact in
                handleCompactNavigationChange(isCompact)
            }
            .onChange(of: scenePhase) { _, newPhase in
                handleScenePhaseChange(newPhase)
            }
            .onChange(of: editMode) { _, newMode in
                handleEditModeChange(newMode)
            }
            .onChange(of: selectedAccountID) { _, newSelection in
                syncRegularSelectedRateLimitTracking(for: newSelection)
                publishWidgetSnapshot()
            }
            .onChange(of: quickActions.pendingAccountDetailID) { _, _ in
                applyPendingQuickActionIfPossible()
            }
            .onChange(of: accounts.map(\.id)) { _, ids in
                handleAccountIDsChange(ids)
            }
            .onChange(of: displayedAccounts.map(\.id)) { _, ids in
                handleDisplayedAccountIDsChange(ids)
            }
            .onChange(of: accounts.map(\.identityKey)) { _, identityKeys in
                handleIdentityKeysChange(identityKeys)
            }
        let contentWithObservers =
            interactionObservedContent
            .task(id: widgetSnapshotFingerprint) {
                publishWidgetSnapshot()
            }
            .task(id: quickActionFingerprint) {
                refreshHomeScreenQuickActions()
            }

        return contentWithObservers
            .sheet(isPresented: $showingSettings) {
                settingsSheetView()
            }
            .alert(item: activeAlert, content: makeAlert)
    }

    private func handleInitialLoad() {
        sortPreferences.synchronize()
        controller.restoreSortPreferences(
            sortCriterionRawValue: sortPreferences.sortCriterionRawValue,
            sortDirectionRawValue: sortPreferences.sortDirectionRawValue
        )
        rateLimitRefreshController.configure(modelContext: modelContext)
        rateLimitRefreshController.reconcileKnownIdentityKeys(accounts.map(\.identityKey))
        rateLimitRefreshController.setScenePhase(scenePhase)
        syncRegularSelectedRateLimitTracking(for: selectedAccountID)
        publishWidgetSnapshot()
        refreshHomeScreenQuickActions()
        applyPendingQuickActionIfPossible()
        consumePendingAccountOpenRequestIfPossible()
        applyPendingSpotlightAccountOpenIfPossible()
        openNotificationSettingsIfRequested()
    }

    private func settingsSheetView() -> some View {
        NavigationStack {
            IOSSettingsView()
        }
        .presentationDragIndicator(.visible)
    }

    private func handleCompactNavigationChange(_ isCompact: Bool) {
        if isCompact {
            selectedAccountID = nil
        }
    }

    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        rateLimitRefreshController.setScenePhase(newPhase)

        guard newPhase == .active else {
            refreshHomeScreenQuickActions()
            return
        }

        publishWidgetSnapshot()
        refreshHomeScreenQuickActions()
        applyPendingQuickActionIfPossible()
        consumePendingAccountOpenRequestIfPossible()
        openNotificationSettingsIfRequested()
    }

    private func openNotificationSettingsIfRequested() {
        guard scenePhase == .active,
              CodexInAppNotificationSettingsSignal.consumePendingOpenNotificationSettingsRequest()
        else {
            return
        }

        showingSettings = true
    }

    private func handleEditModeChange(_ newMode: EditMode) {
        if newMode == .active {
            selectedAccountID = nil
            return
        }

        selectedAccountIDsForEditing.removeAll()
    }

    private func handleAccountIDsChange(_ ids: [UUID]) {
        if let selectedAccountID, !ids.contains(selectedAccountID) {
            self.selectedAccountID = nil
        }

        selectedAccountIDsForEditing.formIntersection(Set(ids))
        applyPendingQuickActionIfPossible()
        applyPendingSpotlightAccountOpenIfPossible()
    }

    private func handleIdentityKeysChange(_ identityKeys: [String]) {
        rateLimitRefreshController.reconcileKnownIdentityKeys(identityKeys)
        applyPendingSpotlightAccountOpenIfPossible()
    }

    private func handleDisplayedAccountIDsChange(_ ids: [UUID]) {
        selectedAccountIDsForEditing.formIntersection(Set(ids))
    }

    private var compactAccountsList: AnyView {
        if displayedAccounts.isEmpty {
            AnyView(emptyState)
        } else if isEditing {
            AnyView(editableAccountsList)
        } else {
            AnyView(
                List {
                    ForEach(displayedAccounts) { account in
                        NavigationLink(value: account.id) {
                            IOSAccountRow(
                                account: account,
                                exportTransferItem: controller.archiveTransferItem(for: account),
                                archiveAvailabilityRefreshToken: controller.archiveAvailabilityRefreshToken
                            )
                        }
                        .contextMenu { rowContextMenu(for: account) }
                        .onAppear {
                            rateLimitRefreshController.setVisible(true, for: account.identityKey)
                        }
                        .onDisappear {
                            rateLimitRefreshController.setVisible(false, for: account.identityKey)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                accountPendingDeletion = account
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                    .onMove { source, destination in
                        controller.move(
                            from: source,
                            to: destination,
                            visibleAccounts: displayedAccounts,
                            in: modelContext
                        )
                    }
                    .moveDisabled(!controller.canEditCustomOrder)
                }
            )
        }
    }

    private var regularAccountsList: AnyView {
        if displayedAccounts.isEmpty {
            AnyView(emptyState)
        } else if isEditing {
            AnyView(editableAccountsList)
        } else {
            AnyView(
                List(selection: $selectedAccountID) {
                    ForEach(displayedAccounts) { account in
                        IOSAccountRow(
                            account: account,
                            exportTransferItem: controller.archiveTransferItem(for: account),
                            archiveAvailabilityRefreshToken: controller.archiveAvailabilityRefreshToken
                        )
                        .tag(account.id)
                        .contextMenu { rowContextMenu(for: account) }
                        .onAppear {
                            rateLimitRefreshController.setVisible(true, for: account.identityKey)
                        }
                        .onDisappear {
                            rateLimitRefreshController.setVisible(false, for: account.identityKey)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                accountPendingDeletion = account
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                    .onMove { source, destination in
                        controller.move(
                            from: source,
                            to: destination,
                            visibleAccounts: displayedAccounts,
                            in: modelContext
                        )
                    }
                    .moveDisabled(!controller.canEditCustomOrder)
                }
            )
        }
    }

    private var editableAccountsList: some View {
        // SwiftUI's built-in multi-selection edit UI is unreliable here when
        // combined with the app's navigation structure, so edit mode uses
        // explicit row checkboxes and a plain movable ForEach.
        List {
            ForEach(displayedAccounts) { account in
                editModeRow(for: account)
                    .onAppear {
                        rateLimitRefreshController.setVisible(true, for: account.identityKey)
                    }
                    .onDisappear {
                        rateLimitRefreshController.setVisible(false, for: account.identityKey)
                    }
            }
            .onMove { source, destination in
                controller.move(
                    from: source,
                    to: destination,
                    visibleAccounts: displayedAccounts,
                    in: modelContext
                )
            }
            .moveDisabled(!controller.canEditCustomOrder)
        }
    }

    private var emptyState: some View {
        let trimmedSearchText = AccountsPresentationLogic.normalizedSearchText(controller.searchText)
        return ContentUnavailableView(
            trimmedSearchText.isEmpty ? "No Accounts" : "No Results",
            systemImage: trimmedSearchText.isEmpty ? "person.crop.rectangle.stack" : "magnifyingglass",
            description: Text(
                trimmedSearchText.isEmpty
                    ? "Accounts captured in Codex Switcher on your Mac appear here through iCloud."
                    : "Try a different search term."
            )
        )
    }

    @ToolbarContentBuilder
    private func rootToolbar() -> some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            sortMenu
        }

        if isEditing {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    deleteSelectedAccounts()
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(selectedAccountIDsForEditing.isEmpty)
                .accessibilityLabel("Delete Selected Accounts")
                .accessibilityIdentifier("ios-delete-selected-accounts-button")
                .tint(.red)
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("ios-settings-button")
        }
    }

    @ViewBuilder
    private func compactAccountDestination(for accountID: UUID) -> some View {
        if let account = account(for: accountID) {
            accountDetailView(for: account)
        } else {
            ContentUnavailableView(
                "Account Unavailable",
                systemImage: "person.crop.circle.badge.exclamationmark",
                description: Text("This account is no longer available.")
            )
        }
    }

    private func account(for accountID: UUID) -> StoredAccount? {
        accounts.first(where: { $0.id == accountID })
    }

    private func refreshHomeScreenQuickActions() {
        quickActions.updateShortcutItems(
            from: controller.homeScreenQuickActionAccounts(
                from: accounts,
                limit: IOSHomeScreenQuickActionCoordinator.maximumAccountQuickActions
            )
        )
    }

    private func publishWidgetSnapshot() {
        WidgetSnapshotPublisher.publish(
            modelContext: modelContext,
            selectedAccountID: selectedAccountID.flatMap { account(for: $0)?.identityKey },
            selectedAccountIsLive: selectedAccountID != nil && !isEditing
        )
    }

    private func applyPendingQuickActionIfPossible() {
        guard scenePhase == .active else {
            return
        }

        guard let accountID = quickActions.pendingAccountDetailID,
              account(for: accountID) != nil else {
            return
        }

        editMode = .inactive
        selectedAccountIDsForEditing.removeAll()
        selectedAccountID = accountID

        if usesCompactNavigation {
            var updatedPath = NavigationPath()
            updatedPath.append(accountID)
            compactNavigationPath = updatedPath
        }

        quickActions.clearPendingAccountDetailID(ifMatching: accountID)
    }

    private func deleteSelectedAccounts() {
        let accountIDsToDelete = selectedAccountIDsForEditing
        guard !accountIDsToDelete.isEmpty else {
            return
        }

        if let selectedAccountID, accountIDsToDelete.contains(selectedAccountID) {
            self.selectedAccountID = nil
        }

        controller.removeAccounts(
            withIDs: accountIDsToDelete,
            from: accounts,
            in: modelContext
        )
        selectedAccountIDsForEditing.removeAll()
    }

    private func removeAccountFromDetailOrList(_ account: StoredAccount) {
        selectedAccountIDsForEditing.remove(account.id)

        if Self.shouldReturnToAccountsHome(
            afterRemovingAccountWithID: account.id,
            usesCompactNavigation: usesCompactNavigation,
            selectedAccountID: selectedAccountID
        ) {
            selectedAccountID = nil
            compactNavigationPath = NavigationPath()
        }

        accountPendingDeletion = nil

        Task { @MainActor in
            // Let SwiftUI apply the navigation state change before the model
            // object disappears. Otherwise compact stacks can keep the stale
            // UUID route alive long enough to show "Account Unavailable."
            await Task.yield()
            controller.remove(account, in: modelContext)
        }
    }

    private func toggleEditingSelection(for accountID: UUID) {
        if selectedAccountIDsForEditing.contains(accountID) {
            selectedAccountIDsForEditing.remove(accountID)
        } else {
            selectedAccountIDsForEditing.insert(accountID)
        }
    }

    @ViewBuilder
    private func accountDetailView(for account: StoredAccount) -> some View {
        let detailView = AccountDetailView(
            account: account,
            controller: controller,
            onRemove: {
                accountPendingDeletion = account
            }
        )
        .id(account.id)

        if usesCompactNavigation {
            detailView
                .onAppear {
                    scheduleCompactSelectedRateLimitTracking(for: account.identityKey)
                }
                .onDisappear {
                    scheduleCompactSelectedRateLimitClear()
                }
        } else {
            detailView
        }
    }

    private var sortMenu: some View {
        Menu {
            ForEach(AccountSortCriterion.allCases) { criterion in
                Button {
                    controller.sortCriterion = criterion
                } label: {
                    rowMenuLabel(
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
                        rowMenuLabel(
                            title: direction.menuTitle,
                            isSelected: controller.sortDirection == direction
                        )
                    }
                }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .accessibilityIdentifier("ios-sort-button")
    }

    private func rowMenuLabel(title: String, isSelected: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()

            if isSelected {
                Image(systemName: "checkmark")
            }
        }
    }

    @ViewBuilder
    private func rowContextMenu(for account: StoredAccount) -> some View {
        Button {
            controller.setPinned(!account.isPinned, for: account, in: modelContext)
        } label: {
            Label(account.isPinned ? "Unpin" : "Pin", systemImage: account.isPinned ? "pin.slash" : "pin")
        }

        Button(role: .destructive) {
            accountPendingDeletion = account
        } label: {
            Label("Remove", systemImage: "trash")
        }
    }

    private func editModeRow(for account: StoredAccount) -> some View {
        let isSelected = selectedAccountIDsForEditing.contains(account.id)

        return Button {
            toggleEditingSelection(for: account.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .accessibilityHidden(true)

                IOSAccountRow(
                    account: account,
                    exportTransferItem: nil,
                    archiveAvailabilityRefreshToken: controller.archiveAvailabilityRefreshToken
                )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AccountsPresentationLogic.displayName(for: account))
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint("Double tap to toggle selection")
    }

    private func makeAlert(for alert: ActiveAlert) -> Alert {
        switch alert {
        case .error(let error):
            return Alert(
                title: Text(error.title),
                message: Text(error.message)
            )
        case .removal(let account):
            return Alert(
                title: Text("Remove \"\(AccountsPresentationLogic.displayName(for: account))\"?"),
                message: Text("Are you sure you want to remove this account from Codex switcher? You will be able to add it again later."),
                primaryButton: .destructive(Text("Remove Account")) {
                    removeAccountFromDetailOrList(account)
                },
                secondaryButton: .cancel {
                    accountPendingDeletion = nil
                }
            )
        }
    }

    private func handleIncomingArchiveURL(_ url: URL) {
        Task { @MainActor in
            let importedAccountIDs = await controller.importAccountArchives(from: [url], in: modelContext)
            focusImportedAccounts(importedAccountIDs)
        }
    }

    private func handleDroppedArchiveURLs(_ urls: [URL]) {
        Task { @MainActor in
            let importedAccountIDs = await controller.importAccountArchives(from: urls, in: modelContext)
            focusImportedAccounts(importedAccountIDs)
        }
    }

    private func focusImportedAccounts(_ importedAccountIDs: [UUID]) {
        guard let importedAccountID = importedAccountIDs.last else {
            return
        }

        editMode = .inactive
        selectedAccountIDsForEditing.removeAll()
        selectedAccountID = importedAccountID
        controller.searchText = ""

        if usesCompactNavigation {
            var updatedPath = NavigationPath()
            updatedPath.append(importedAccountID)
            compactNavigationPath = updatedPath
        }
    }

    @discardableResult
    private func focusAccount(withIdentityKey identityKey: String) -> Bool {
        let normalizedIdentityKey = identityKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let account = accounts.first(where: { $0.identityKey == normalizedIdentityKey }) else {
            return false
        }

        editMode = .inactive
        selectedAccountIDsForEditing.removeAll()
        selectedAccountID = account.id
        controller.searchText = ""
        pendingSpotlightAccountIdentityKey = nil

        if usesCompactNavigation {
            var updatedPath = NavigationPath()
            updatedPath.append(account.id)
            compactNavigationPath = updatedPath
        }

        return true
    }

    private func consumePendingAccountOpenRequestIfPossible() {
        guard scenePhase == .active else {
            return
        }

        do {
            guard let request = try CodexPendingAccountOpenRequestStore().consume() else {
                return
            }

            if !focusAccount(withIdentityKey: request.identityKey) {
                pendingSpotlightAccountIdentityKey = request.identityKey
            }
        } catch {
            Self.logger.error(
                "Couldn't consume pending account-open request: \(String(describing: error), privacy: .private)"
            )
        }
    }

    private func applyPendingSpotlightAccountOpenIfPossible() {
        guard let pendingSpotlightAccountIdentityKey else {
            return
        }

        _ = focusAccount(withIdentityKey: pendingSpotlightAccountIdentityKey)
    }

    private func syncRegularSelectedRateLimitTracking(for accountID: UUID?) {
        guard !usesCompactNavigation else {
            return
        }

        let identityKey = accountID.flatMap { account(for: $0)?.identityKey }
        rateLimitRefreshController.setSelected(identityKey: identityKey)

        if let identityKey {
            rateLimitRefreshController.refreshNow(for: identityKey)
        }
    }

    private func scheduleCompactSelectedRateLimitTracking(for identityKey: String) {
        Task { @MainActor in
            // Defer the refresh-state mutation until after SwiftUI finishes the
            // current navigation update to avoid duplicate navigation requests
            // in the same frame.
            await Task.yield()
            rateLimitRefreshController.setSelected(identityKey: identityKey)
            rateLimitRefreshController.refreshNow(for: identityKey)
        }
    }

    private func scheduleCompactSelectedRateLimitClear() {
        Task { @MainActor in
            // Compact navigation destroys and recreates detail views as the
            // stack changes, so clear selection on the next turn instead of
            // during the same transition frame.
            await Task.yield()
            if usesCompactNavigation {
                rateLimitRefreshController.setSelected(identityKey: nil)
            }
        }
    }
}

#Preview("Accounts") {
    AccountsRootView()
        .modelContainer(IOSPreviewData.makeContainer())
}

#Preview("Empty") {
    AccountsRootView()
        .modelContainer(IOSPreviewData.makeContainer(scenario: .empty))
}
