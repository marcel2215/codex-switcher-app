//
//  AccountsRootView.swift
//  Codex Switcher iOS App
//
//  Created by Codex on 2026-04-11.
//

import SwiftData
import SwiftUI

struct AccountsRootView: View {
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
    @Query private var accounts: [StoredAccount]

    @State private var controller = IOSAccountsController()
    @State private var selectedAccountID: UUID?
    @State private var showingSettings = false
    @State private var accountPendingDeletion: StoredAccount?
    @State private var sortPreferences = IOSCloudSortPreferences()

    private var displayedAccounts: [StoredAccount] {
        controller.displayedAccounts(from: accounts)
    }

    private var selectedAccount: StoredAccount? {
        accounts.first(where: { $0.id == selectedAccountID })
    }

    private var usesCompactNavigation: Bool {
        horizontalSizeClass == .compact
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
        @Bindable var bindableController = controller

        Group {
            if usesCompactNavigation {
                NavigationStack {
                    compactAccountsList
                        .navigationTitle("Accounts")
                        .navigationDestination(for: UUID.self, destination: compactAccountDestination)
                        .searchable(text: $bindableController.searchText, prompt: "Search")
                        .toolbar(content: rootToolbar)
                }
            } else {
                NavigationSplitView {
                    regularAccountsList
                        .navigationTitle("Accounts")
                        .searchable(text: $bindableController.searchText, prompt: "Search")
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
            }
        }
        .task {
            sortPreferences.synchronize()
            controller.restoreSortPreferences(
                sortCriterionRawValue: sortPreferences.sortCriterionRawValue,
                sortDirectionRawValue: sortPreferences.sortDirectionRawValue
            )
        }
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
        .onChange(of: usesCompactNavigation) { _, isCompact in
            if isCompact {
                selectedAccountID = nil
            }
        }
        .onChange(of: accounts.map(\.id)) { _, ids in
            if let selectedAccountID, !ids.contains(selectedAccountID) {
                self.selectedAccountID = nil
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                IOSSettingsView()
            }
        }
        .alert(item: activeAlert) { alert in
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
                        if selectedAccountID == account.id {
                            selectedAccountID = nil
                        }

                        controller.remove(account, in: modelContext)
                        accountPendingDeletion = nil
                    },
                    secondaryButton: .cancel {
                        accountPendingDeletion = nil
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var compactAccountsList: some View {
        if displayedAccounts.isEmpty {
            emptyState
        } else {
            List {
                accountRows { account in
                    NavigationLink(value: account.id) {
                        IOSAccountRow(account: account)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var regularAccountsList: some View {
        if displayedAccounts.isEmpty {
            emptyState
        } else {
            List(selection: $selectedAccountID) {
                accountRows { account in
                    IOSAccountRow(account: account)
                        .tag(account.id)
                }
            }
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

        if controller.canEditCustomOrder && displayedAccounts.count > 1 {
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
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

    private func accountDetailView(for account: StoredAccount) -> some View {
        AccountDetailView(
            account: account,
            controller: controller,
            onRemove: {
                accountPendingDeletion = account
            }
        )
    }

    @ViewBuilder
    private func accountRows<RowContent: View>(
        @ViewBuilder rowContent: @escaping (StoredAccount) -> RowContent
    ) -> some View {
        ForEach(displayedAccounts) { account in
            rowContent(account)
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
}

#Preview("Accounts") {
    AccountsRootView()
        .modelContainer(IOSPreviewData.makeContainer())
}

#Preview("Empty") {
    AccountsRootView()
        .modelContainer(IOSPreviewData.makeContainer(scenario: .empty))
}
