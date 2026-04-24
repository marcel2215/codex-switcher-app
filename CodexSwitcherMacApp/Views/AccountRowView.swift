//
//  AccountRowView.swift
//  Codex Switcher Mac App
//
//  Created by Marcel Kwiatkowski on 2026-04-07.
//

import SwiftUI

struct AccountRowView: View {
    let account: StoredAccount
    let isCurrentAccount: Bool
    let isSelected: Bool
    let isRenaming: Bool
    let onCommitRename: (String) -> Void
    let onCancelRename: () -> Void

    @FocusState private var isRenameFieldFocused: Bool
    @State private var draftName = ""

    var body: some View {
        rowContent
    }

    private var rowContent: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: AccountIconOption.resolve(from: account.iconSystemName).systemName)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 1) {
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
                    accountListDisplayName
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .allowsHitTesting(false)
                }

                AccountMetadataText(
                    lastLoginAt: account.lastLoginAt,
                    sevenDayLimitUsedPercent: account.sevenDayLimitUsedPercent,
                    fiveHourLimitUsedPercent: account.fiveHourLimitUsedPercent,
                    sevenDayResetsAt: account.sevenDayResetsAt,
                    fiveHourResetsAt: account.fiveHourResetsAt,
                    isUnavailable: account.isUnavailable,
                    font: .subheadline
                )
                .allowsHitTesting(false)
            }

            Spacer(minLength: 0)

            currentAccountIndicator
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 1)
        // The list container owns selection, primary action, and drag behavior.
        // Keep the row itself presentation-only so the entire row remains one
        // native hit target instead of a stack of competing gesture regions.
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var currentAccountIndicator: some View {
        // Always reserve the trailing indicator slot so the progress meters
        // line up consistently whether or not this row is the current account.
        Group {
            if isCurrentAccount {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                    .help("Currently active in Codex")
                    .allowsHitTesting(false)
            } else {
                Color.clear
                    .allowsHitTesting(false)
            }
        }
        .frame(width: 16, height: 16)
    }

    private func commitRename() {
        onCommitRename(draftName)
    }

    private var accountListDisplayName: Text {
        let parts = AccountsPresentationLogic.accountListDisplayNameParts(for: account)

        guard let unavailableSuffix = parts.unavailableSuffix else {
            return Text(parts.name)
        }

        return Text(parts.name) + Text(unavailableSuffix).foregroundStyle(.red)
    }
}
