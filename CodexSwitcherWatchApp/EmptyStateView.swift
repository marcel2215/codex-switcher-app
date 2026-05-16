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
                ? L10n.string("No Accounts", comment: "Empty account list title.")
                : L10n.string("No Results", comment: "Empty account search results title."),
            systemImage: normalizedSearchText.isEmpty ? "person.crop.rectangle.stack" : "magnifyingglass",
            description: Text(
                normalizedSearchText.isEmpty
                    ? L10n.string(
                        "Accounts captured in Codex Switcher on your Mac appear here through iCloud.",
                        comment: "Empty watch account list description."
                    )
                    : L10n.string("Try a different search term.", comment: "Empty search results description.")
            )
        )
    }
}
