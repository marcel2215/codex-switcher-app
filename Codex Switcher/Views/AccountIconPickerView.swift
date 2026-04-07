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

    private let columns = Array(repeating: GridItem(.fixed(44), spacing: 12), count: 4)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(AccountIconOption.allCases) { icon in
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
        .padding(20)
        .frame(width: 244)
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
