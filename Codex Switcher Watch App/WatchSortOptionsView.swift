//
//  WatchSortOptionsView.swift
//  Codex Switcher Watch App
//
//  Created by Codex on 2026-04-12.
//

import SwiftUI

struct WatchSortOptionsView: View {
    @Environment(\.dismiss) private var dismiss

    let sortCriterion: AccountSortCriterion
    let sortDirection: SortDirection
    let onSelectCriterion: (AccountSortCriterion) -> Void
    let onSelectDirection: (SortDirection) -> Void

    var body: some View {
        List {
            Section("Sort By") {
                ForEach(AccountSortCriterion.allCases) { criterion in
                    Button {
                        onSelectCriterion(criterion)
                    } label: {
                        rowLabel(
                            title: criterion.menuTitle,
                            isSelected: sortCriterion == criterion
                        )
                    }
                    .foregroundStyle(.primary)
                }
            }

            if sortCriterion != .custom {
                Section("Direction") {
                    ForEach(SortDirection.allCases) { direction in
                        Button {
                            onSelectDirection(direction)
                        } label: {
                            rowLabel(
                                title: direction.menuTitle,
                                isSelected: sortDirection == direction
                            )
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
        }
        .navigationTitle("Sort")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }

    private func rowLabel(title: String, isSelected: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()

            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
            }
        }
    }
}
