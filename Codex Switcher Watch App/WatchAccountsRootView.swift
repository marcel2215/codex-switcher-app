//
//  WatchAccountsRootView.swift
//  Codex Switcher Watch App
//
//  Created by Codex on 2026-04-12.
//

import SwiftData
import SwiftUI

struct WatchAccountsRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var accounts: [StoredAccount]

    @State private var refreshController = WatchRateLimitRefreshController()
    @State private var sortPreferences = CloudSortPreferences()
    @State private var searchText = ""
    @State private var sortCriterion: AccountSortCriterion = .dateAdded
    @State private var sortDirection: SortDirection = .ascending
    @State private var showingSortOptions = false
    @State private var showingSettings = false
    @State private var presentedError: PresentedError?

    private var displayedAccounts: [StoredAccount] {
        AccountsPresentationLogic.displayedAccounts(
            from: accounts,
            searchText: searchText,
            sortCriterion: sortCriterion,
            sortDirection: sortDirection
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if displayedAccounts.isEmpty {
                    WatchEmptyStateView(searchText: searchText)
                        .onAppear {
                            clearSelectedRateLimitTracking()
                        }
                } else {
                    List(displayedAccounts) { account in
                        NavigationLink {
                            WatchAccountDetailView(
                                account: account,
                                refreshController: refreshController,
                                onError: { presentedError = $0 }
                            )
                        } label: {
                            WatchAccountRow(account: account)
                                .onAppear {
                                    refreshController.setVisible(true, for: account.identityKey)
                                }
                                .onDisappear {
                                    refreshController.setVisible(false, for: account.identityKey)
                                }
                        }
                    }
                    .refreshable {
                        await refreshController.refreshTrackedAccountsNow()
                    }
                    .onAppear {
                        clearSelectedRateLimitTracking()
                    }
                }
            }
            .navigationTitle("Accounts")
            .searchable(text: $searchText, prompt: "Search")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingSortOptions = true
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .accessibilityLabel("Sort")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
        }
        .sheet(isPresented: $showingSortOptions) {
            NavigationStack {
                WatchSortOptionsView(
                    sortCriterion: sortCriterion,
                    sortDirection: sortDirection,
                    onSelectCriterion: applySortCriterion,
                    onSelectDirection: applySortDirection
                )
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                WatchSettingsView()
            }
        }
        .alert(item: $presentedError) { error in
            Alert(
                title: Text(error.title),
                message: Text(error.message)
            )
        }
        .task {
            sortPreferences.synchronize()
            restoreSortPreferences()

            refreshController.configure(modelContext: modelContext)
            refreshController.reconcileKnownIdentityKeys(accounts.map(\.identityKey))
            refreshController.setScenePhase(scenePhase)
        }
        .onChange(of: scenePhase) { _, newPhase in
            refreshController.setScenePhase(newPhase)
        }
        .onChange(of: accounts.map(\.identityKey)) { _, newIdentityKeys in
            refreshController.reconcileKnownIdentityKeys(newIdentityKeys)
        }
        .onChange(of: sortPreferences.sortCriterionRawValue) { _, _ in
            restoreSortPreferences()
        }
        .onChange(of: sortPreferences.sortDirectionRawValue) { _, _ in
            restoreSortPreferences()
        }
    }

    private func restoreSortPreferences() {
        let resolvedCriterion = AccountSortCriterion(rawValue: sortPreferences.sortCriterionRawValue) ?? .dateAdded
        let resolvedDirection = AccountsPresentationLogic.normalizedSortDirection(
            for: resolvedCriterion,
            requestedDirection: SortDirection(rawValue: sortPreferences.sortDirectionRawValue) ?? .ascending
        )

        if sortCriterion != resolvedCriterion {
            sortCriterion = resolvedCriterion
        }

        if sortDirection != resolvedDirection {
            sortDirection = resolvedDirection
        }
    }

    private func applySortCriterion(_ criterion: AccountSortCriterion) {
        let resolvedDirection = AccountsPresentationLogic.normalizedSortDirection(
            for: criterion,
            requestedDirection: sortDirection
        )

        guard sortCriterion != criterion || sortDirection != resolvedDirection else {
            return
        }

        sortCriterion = criterion
        sortDirection = resolvedDirection
        persistSortPreferences()
    }

    private func applySortDirection(_ direction: SortDirection) {
        let resolvedDirection = AccountsPresentationLogic.normalizedSortDirection(
            for: sortCriterion,
            requestedDirection: direction
        )

        guard sortDirection != resolvedDirection else {
            return
        }

        sortDirection = resolvedDirection
        persistSortPreferences()
    }

    private func persistSortPreferences() {
        sortPreferences.persist(
            sortCriterionRawValue: sortCriterion.rawValue,
            sortDirectionRawValue: sortDirection.rawValue
        )
    }

    private func clearSelectedRateLimitTracking() {
        Task { @MainActor in
            // Clear selection after the navigation stack settles so pushing into
            // child editors under an account detail does not immediately drop
            // the selected-account refresh cadence.
            await Task.yield()
            refreshController.setSelected(identityKey: nil)
        }
    }
}

#Preview("Accounts") {
    WatchAccountsRootView()
        .modelContainer(WatchPreviewData.makeContainer())
}

#Preview("Empty") {
    WatchAccountsRootView()
        .modelContainer(WatchAppBootstrap.make(isStoredInMemoryOnly: true).modelContainerForPreview)
}
