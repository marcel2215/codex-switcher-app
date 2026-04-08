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

                Text(lastLoginDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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

    /// Formats the account's last-login timestamp using the app's constrained wording.
    /// Keep this in sync with the row-copy requirements: only "this hour",
    /// "X hour(s) ago", and "X day(s) ago" are valid outputs.
    static func makeLastLoginDescription(from lastLoginAt: Date?, relativeTo now: Date = .now) -> String {
        guard let lastLoginAt else {
            return "Last login: never"
        }

        // Clock skew or manual system time changes should not produce "in the future".
        let elapsedSeconds = max(now.timeIntervalSince(lastLoginAt), 0)
        let hourInSeconds: TimeInterval = 60 * 60
        let dayInSeconds: TimeInterval = 24 * hourInSeconds

        if elapsedSeconds < hourInSeconds {
            return "Last login: this hour"
        }

        if elapsedSeconds < dayInSeconds {
            let hoursAgo = Int(elapsedSeconds / hourInSeconds)
            let hourLabel = hoursAgo == 1 ? "hour" : "hours"
            return "Last login: \(hoursAgo) \(hourLabel) ago"
        }

        let daysAgo = max(Int(elapsedSeconds / dayInSeconds), 1)
        let dayLabel = daysAgo == 1 ? "day" : "days"
        return "Last login: \(daysAgo) \(dayLabel) ago"
    }

    private var lastLoginDescription: String {
        Self.makeLastLoginDescription(from: account.lastLoginAt)
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
