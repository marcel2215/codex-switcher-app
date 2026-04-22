//
//  AccountIconPickerView.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-07.
//

import SwiftUI

struct AccountIconPickerView: View {
    let selectedIcon: AccountIconOption
    let onSelect: (AccountIconOption) -> Void
    let onCancel: () -> Void

    private let columns = Array(repeating: GridItem(.fixed(44), spacing: 12), count: 5)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Text("Choose Icon")
                    .font(.headline)

                Spacer(minLength: 0)

                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel")
                .help("Close icon picker")
            }

            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(AccountIconOption.displayOrder) { icon in
                        Button {
                            onSelect(icon)
                        } label: {
                            Image(systemName: icon.systemName)
                                .font(.title3)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(icon == selectedIcon ? Color.white : Color.primary)
                                .frame(width: 44, height: 44)
                                .background(background(for: icon))
                        }
                        .buttonStyle(.plain)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .accessibilityLabel(icon.title)
                        .help(icon.title)
                    }
                }
            }
            .frame(maxHeight: 260)
        }
        .padding(20)
        .frame(width: 332)
    }

    @ViewBuilder
    private func background(for icon: AccountIconOption) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(icon == selectedIcon ? Color.accentColor : Color.secondary.opacity(0.12))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        icon == selectedIcon ? Color.accentColor : Color.secondary.opacity(0.18),
                        lineWidth: 1
                    )
            }
    }
}
