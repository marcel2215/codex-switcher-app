//
//  EmptyStateView.swift
//  Codex Switcher Watch App
//
//  Created by Marcel Kwiatkowski on 2026-04-12.
//

import SwiftUI

struct WatchEmptyStateView: View {
    let searchText: String

    private var normalizedSearchText: String {
        AccountsPresentationLogic.normalizedSearchText(searchText)
    }

    var body: some View {
        ContentUnavailableView(
            normalizedSearchText.isEmpty
                ? L10n.string("empty.accounts.title", defaultValue: "No Accounts")
                : L10n.string("empty.searchResults.title", defaultValue: "No Results"),
            systemImage: normalizedSearchText.isEmpty ? "person.crop.rectangle.stack" : "magnifyingglass",
            description: Text(
                normalizedSearchText.isEmpty
                    ? L10n.string(
                        "empty.watch.accounts.description",
                        defaultValue: "Accounts captured in Codex Switcher on your Mac appear here through iCloud."
                    )
                    : L10n.string("empty.searchResults.description", defaultValue: "Try a different search term.")
            )
        )
    }
}
