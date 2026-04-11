//
//  AccountDetailView.swift
//  Codex Switcher iOS App
//
//  Created by Codex on 2026-04-11.
//

import SwiftData
import SwiftUI

struct AccountDetailView: View {
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
                TextField("Name", text: $draftName)
                    .submitLabel(.done)
                    .onSubmit(persistDraftName)

                if let emailHint {
                    LabeledContent("Email") {
                        Text(emailHint)
                            .foregroundStyle(.secondary)
                    }
                }

                if let accountIdentifier {
                    LabeledContent("Identifier") {
                        Text(accountIdentifier)
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

            Section("Appearance") {
                NavigationLink {
                    IOSAccountIconPickerView(account: account, controller: controller)
                } label: {
                    LabeledContent("Icon") {
                        Label(
                            AccountIconOption.resolve(from: account.iconSystemName).title,
                            systemImage: AccountIconOption.resolve(from: account.iconSystemName).systemName
                        )
                    }
                }
            }

            Section {
                Button("Remove Account", role: .destructive, action: onRemove)
            } header: {
                Text("Danger Zone")
            } footer: {
                Text("Removing an account deletes the saved account entry from your iCloud-synced list. It does not remotely switch or log out your Mac.")
            }
        }
        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear(perform: persistDraftName)
    }

    private var emailHint: String? {
        let trimmedEmailHint = account.emailHint?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedEmailHint.isEmpty ? nil : trimmedEmailHint
    }

    private var accountIdentifier: String? {
        let trimmedIdentifier = account.accountIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedIdentifier.isEmpty ? nil : trimmedIdentifier
    }

    private func persistDraftName() {
        guard !account.isDeleted else {
            return
        }

        controller.commitRename(for: account, proposedName: draftName, in: modelContext)
        draftName = account.name
    }
}
