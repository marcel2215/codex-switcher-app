//
//  AccountsRootView.swift
//  Codex Switcher iOS App
//
//  Created by Codex on 2026-04-11.
//

import SwiftData
import SwiftUI

struct AccountsRootView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext
    @Query private var accounts: [StoredAccount]

    @State private var controller = IOSAccountsController()
    @State private var selectedAccountID: UUID?
    @State private var showingSettings = false
    @State private var accountPendingDeletion: StoredAccount?

    @AppStorage("ios.sortCriterion") private var persistedSortCriterionRawValue = AccountSortCriterion.dateAdded.rawValue
    @AppStorage("ios.sortDirection") private var persistedSortDirectionRawValue = SortDirection.ascending.rawValue

    private var displayedAccounts: [StoredAccount] {
        controller.displayedAccounts(from: accounts)
    }

    private var selectedAccount: StoredAccount? {
        accounts.first(where: { $0.id == selectedAccountID })
    }

    private var usesCompactNavigation: Bool {
        horizontalSizeClass == .compact
    }

    var body: some View {
        @Bindable var bindableController = controller

        Group {
            if usesCompactNavigation {
                NavigationStack {
                    compactAccountsList
                        .navigationTitle("Accounts")
                        .navigationDestination(for: UUID.self, destination: compactAccountDestination)
                }
                .searchable(text: $bindableController.searchText, prompt: "Search")
                .toolbar(content: rootToolbar)
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
            controller.restoreSortPreferences(
                sortCriterionRawValue: persistedSortCriterionRawValue,
                sortDirectionRawValue: persistedSortDirectionRawValue
            )
        }
        .onChange(of: controller.sortCriterion) { _, newValue in
            persistedSortCriterionRawValue = newValue.rawValue
        }
        .onChange(of: controller.sortDirection) { _, newValue in
            persistedSortDirectionRawValue = newValue.rawValue
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
        .alert(item: $bindableController.presentedError) { error in
            Alert(title: Text(error.title), message: Text(error.message))
        }
        .confirmationDialog(
            "Remove Account?",
            isPresented: Binding(
                get: { accountPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        accountPendingDeletion = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let account = accountPendingDeletion {
                Button("Remove Account", role: .destructive) {
                    if selectedAccountID == account.id {
                        selectedAccountID = nil
                    }

                    controller.remove(account, in: modelContext)
                    accountPendingDeletion = nil
                }
            }

            Button("Cancel", role: .cancel) {
                accountPendingDeletion = nil
            }
        } message: {
            Text("This removes the saved account from your iCloud-synced account list. It does not switch the account currently active on your Mac.")
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
            if controller.canEditCustomOrder && displayedAccounts.count > 1 {
                EditButton()
            }
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            sortMenu

            Button {
                showingSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
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
            Section("Sort By") {
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
            }

            if controller.sortCriterion != .custom {
                Section("Direction") {
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
