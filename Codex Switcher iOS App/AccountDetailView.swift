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

    @Environment(\.modelContext) private var modelContext

    let account: StoredAccount
    let controller: IOSAccountsController
    let onRemove: () -> Void

    @State private var draftName: String

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
            }

            Section {
                LabeledContent("7-Day Remaining") {
                    Text(AccountDisplayFormatter.detailedPercentDescription(account.sevenDayLimitUsedPercent))
                }

                LabeledContent("5-Hour Remaining") {
                    Text(AccountDisplayFormatter.detailedPercentDescription(account.fiveHourLimitUsedPercent))
                }

                LabeledContent("Last Login") {
                    Text(AccountDisplayFormatter.lastLoginValueDescription(from: account.lastLoginAt))
                }

                LabeledContent("Last Updated") {
                    if let rateLimitsObservedAt = account.rateLimitsObservedAt {
                        Text(rateLimitsObservedAt, style: .relative)
                    } else {
                        Text("Not synced yet")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Rate Limits")
            } footer: {
                Text("Rate limits are synced from your Mac. The iPhone and iPad app does not refresh them directly.")
            }

            Section {
                Button("Remove Account", role: .destructive, action: onRemove)
            } header: {
                Text("Danger Zone")
            } footer: {
                Text("Removing an account deletes the saved account entry from your iCloud-synced list. It does not remotely switch or log out your Mac.")
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
