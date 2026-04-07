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
        HStack(alignment: .top, spacing: 12) {
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

                Text(lastLoginDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if isCurrentAccount {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
                    .help("Currently active in Codex")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var lastLoginDescription: String {
        guard let lastLoginAt = account.lastLoginAt else {
            return "Never switched with Codex Switcher"
        }

        return "Last login: \(lastLoginAt.formatted(date: .abbreviated, time: .shortened))"
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
