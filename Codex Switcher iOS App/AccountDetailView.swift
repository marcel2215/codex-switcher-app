//
//  AccountDetailView.swift
//  Codex Switcher iOS App
//
//  Created by Codex on 2026-04-11.
//

import SwiftData
import SwiftUI

struct AccountDetailView: View {
    private enum DetailDestination: Hashable {
        case name
        case icon
    }

    private enum ResetRow: Hashable {
        case sevenDay
        case fiveHour
    }

    @Environment(\.modelContext) private var modelContext

    let account: StoredAccount
    let controller: IOSAccountsController
    let onRemove: () -> Void

    @State private var draftName: String
    @State private var resetDisplayModes: [ResetRow: AccountDisplayFormatter.ResetTimeDisplayMode] = [
        .sevenDay: .relative,
        .fiveHour: .relative,
    ]

    init(
        account: StoredAccount,
        controller: IOSAccountsController,
        onRemove: @escaping () -> Void
    ) {
        self.account = account
        self.controller = controller
        self.onRemove = onRemove
        _draftName = State(initialValue: account.name)
    }

    var body: some View {
        Form {
            Section("Account") {
                NavigationLink(value: DetailDestination.name) {
                    LabeledContent("Name") {
                        Text(displayName)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .multilineTextAlignment(.trailing)
                    }
                }

                NavigationLink(value: DetailDestination.icon) {
                    LabeledContent("Icon") {
                        HStack(spacing: 8) {
                            Image(systemName: selectedIcon.systemName)

                            Text(selectedIcon.title)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .foregroundStyle(.secondary)
                    }
                }

                LabeledContent("Last Login") {
                    Text(AccountDisplayFormatter.lastLoginValueDescription(from: account.lastLoginAt))
                }
            }

            Section("Rate Limits") {
                LabeledContent("5-Hour Remaining") {
                    usageValueText(account.fiveHourLimitUsedPercent)
                }

                LabeledContent("5-Hour Reset") {
                    resetValueButton(account.fiveHourResetsAt, row: .fiveHour)
                }

                LabeledContent("7-Day Remaining") {
                    usageValueText(account.sevenDayLimitUsedPercent)
                }

                LabeledContent("7-Day Reset") {
                    resetValueButton(account.sevenDayResetsAt, row: .sevenDay)
                }
            }

            Section {
                Button(role: .destructive, action: onRemove) {
                    Label("Remove Account", systemImage: "trash")
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Danger Zone")
            }
        }
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: DetailDestination.self, destination: destinationView)
        .onDisappear(perform: persistDraftName)
    }

    private var emailHint: String? {
        let trimmedEmailHint = account.emailHint?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedEmailHint.isEmpty ? nil : trimmedEmailHint
    }

    private var displayName: String {
        AccountsPresentationLogic.displayName(
            name: draftName,
            emailHint: emailHint,
            accountIdentifier: account.accountIdentifier,
            identityKey: account.identityKey
        )
    }

    private var nameEditorPrompt: String {
        emailHint ?? ""
    }

    private var selectedIcon: AccountIconOption {
        AccountIconOption.resolve(from: account.iconSystemName)
    }

    private func usageValueText(_ value: Int?) -> some View {
        let description = AccountDisplayFormatter.detailedPercentDescription(value)

        return Text(description)
            .foregroundStyle(.secondary)
    }

    private func resetValueButton(_ value: Date?, row: ResetRow) -> some View {
        Button {
            toggleResetDisplayMode(for: row)
        } label: {
            Text(
                AccountDisplayFormatter.resetTimeDescription(
                    until: value,
                    displayMode: resetDisplayModes[row] ?? .relative
                )
            )
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .disabled(value == nil)
        .accessibilityHint(value == nil ? "Reset time unavailable" : "Double tap to switch between relative and absolute time")
    }

    private func toggleResetDisplayMode(for row: ResetRow) {
        let currentMode = resetDisplayModes[row] ?? .relative
        resetDisplayModes[row] = currentMode == .relative ? .absolute : .relative
    }

    @ViewBuilder
    private func destinationView(for destination: DetailDestination) -> some View {
        switch destination {
        case .name:
            IOSAccountNameEditorView(
                draftName: $draftName,
                placeholder: nameEditorPrompt,
                onSave: persistDraftName
            )
        case .icon:
            IOSAccountIconPickerView(account: account, controller: controller)
        }
    }

    private func persistDraftName() {
        guard !account.isDeleted else {
            return
        }

        controller.commitRename(for: account, proposedName: draftName, in: modelContext)
        draftName = account.name
    }
}
