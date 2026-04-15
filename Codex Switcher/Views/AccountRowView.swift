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
    let exportTransferItem: CodexAccountArchiveTransferItem
    let onRemove: () -> Void
    let onSelect: () -> Void
    let onDoubleClick: () -> Void
    let onCommitRename: (String) -> Void
    let onCancelRename: () -> Void

    @FocusState private var isRenameFieldFocused: Bool
    @State private var draftName = ""
    @State private var isArchiveExportAvailable = false

    var body: some View {
        rowContent
            .modifier(
                ReorderModifier(
                    isEnabled: canReorder,
                    dragPayload: account.id.uuidString,
                    exportTransferItem: exportTransferItem,
                    isArchiveExportAvailable: isArchiveExportAvailable
                )
            )
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button("Remove", systemImage: "trash", role: .destructive, action: onRemove)
            }
            .task(id: exportTransferItem.availabilityKey) {
                isArchiveExportAvailable = await exportTransferItem.canExport()
            }
    }

    private var rowContent: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: AccountIconOption.resolve(from: account.iconSystemName).systemName)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)

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
                    Text(account.name)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                }

                AccountMetadataText(
                    lastLoginAt: account.lastLoginAt,
                    sevenDayLimitUsedPercent: account.sevenDayLimitUsedPercent,
                    fiveHourLimitUsedPercent: account.fiveHourLimitUsedPercent,
                    sevenDayResetsAt: account.sevenDayResetsAt,
                    fiveHourResetsAt: account.fiveHourResetsAt,
                    font: .subheadline
                )
            }

            Spacer(minLength: 0)

            currentAccountIndicator
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isRenaming else {
                return
            }

            onSelect()
        }
        .onTapGesture(count: 2) {
            guard !isRenaming else {
                return
            }

            // Keep activation on the row itself so double-click still works
            // even when macOS drag export is powered by a custom NSItemProvider.
            onSelect()
            onDoubleClick()
        }
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
            } else {
                Color.clear
            }
        }
        .frame(width: 16, height: 16)
    }

    private func commitRename() {
        onCommitRename(draftName)
    }
}

private struct ReorderModifier: ViewModifier {
    let isEnabled: Bool
    let dragPayload: String
    let exportTransferItem: CodexAccountArchiveTransferItem
    let isArchiveExportAvailable: Bool

    func body(content: Content) -> some View {
#if os(macOS)
        if isArchiveExportAvailable {
            content.onDrag {
                exportTransferItem.macOSItemProvider(includeReorderToken: isEnabled)
            }
        } else if isEnabled {
            content.onDrag {
                NSItemProvider(object: dragPayload as NSString)
            }
        } else {
            content
        }
#else
        if isArchiveExportAvailable {
            content.draggable(exportTransferItem)
        } else if isEnabled {
            content.draggable(dragPayload)
        } else {
            content
        }
#endif
    }
}
