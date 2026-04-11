//
//  AccountRowView.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-07.
//

import SwiftUI

struct AccountRowView: View {
    let account: StoredAccount
    let isCurrentAccount: Bool
    let isSelected: Bool
    let isRenaming: Bool
    let canReorder: Bool
    let onRemove: () -> Void
    let onCommitRename: (String) -> Void
    let onCancelRename: () -> Void

    @FocusState private var isRenameFieldFocused: Bool
    @State private var draftName = ""

    var body: some View {
        rowContent
            .modifier(ReorderModifier(isEnabled: canReorder, dragPayload: account.id.uuidString))
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button("Remove", systemImage: "trash", role: .destructive, action: onRemove)
            }
    }

    private var rowContent: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: AccountIconOption.resolve(from: account.iconSystemName).systemName)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                if isRenaming {
                    TextField("", text: $draftName)
                        .textFieldStyle(.plain)
                        .focused($isRenameFieldFocused)
                        .onSubmit(commitRename)
                        .onChange(of: isRenameFieldFocused) { _, focused in
                            if !focused, isRenaming {
                                commitRename()
                            }
                        }
                        .task(id: isRenaming) {
                            guard isRenaming else {
                                return
                            }
                            draftName = account.name
                            isRenameFieldFocused = true
                        }
                        .onKeyPress(.escape) {
                            onCancelRename()
                            return .handled
                        }
                } else {
                    Text(account.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                }

                AccountMetadataText(
                    lastLoginAt: account.lastLoginAt,
                    sevenDayLimitUsedPercent: account.sevenDayLimitUsedPercent,
                    fiveHourLimitUsedPercent: account.fiveHourLimitUsedPercent,
                    font: .subheadline
                )
            }

            Spacer(minLength: 0)

            if isCurrentAccount {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                    .help("Currently active in Codex")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func commitRename() {
        onCommitRename(draftName)
    }
}

private struct ReorderModifier: ViewModifier {
    let isEnabled: Bool
    let dragPayload: String

    func body(content: Content) -> some View {
        if isEnabled {
            content.draggable(dragPayload)
        } else {
            content
        }
    }
}
