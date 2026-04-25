//
//  AccountDetailsWindowView.swift
//  Codex Switcher Mac App
//
//  Created by Codex on 2026-04-25.
//

import SwiftData
import SwiftUI

enum AccountDetailsWindowID {
    static let details = "account-details"
}

struct AccountDetailsWindowView: View {
    let accountID: UUID?
    @Bindable var controller: AppController

    @Environment(\.modelContext) private var modelContext
    @Query private var accounts: [StoredAccount]

    var body: some View {
        Group {
            if let selectedAccount {
                NavigationStack {
                    AccountDetailsWindowForm(account: selectedAccount, controller: controller)
                }
            } else {
                ContentUnavailableView(
                    "Account Not Available",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("The selected account no longer exists.")
                )
            }
        }
        .task {
            controller.configure(modelContext: modelContext, undoManager: nil)
        }
        .alert(item: $controller.presentedAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .alert(item: $controller.unavailableAccountRecoveryPrompt) { prompt in
            Alert(
                title: Text("Account Unavailable"),
                message: Text(unavailableAccountMessage(for: prompt)),
                primaryButton: .destructive(Text("Remove")) {
                    controller.removeUnavailableAccountFromPrompt(prompt)
                },
                secondaryButton: .cancel(Text("Keep")) {
                    controller.keepUnavailableAccountFromPrompt()
                }
            )
        }
    }

    private var selectedAccount: StoredAccount? {
        guard let accountID else {
            return nil
        }

        return accounts.first { $0.id == accountID }
    }

    private func unavailableAccountMessage(for prompt: UnavailableAccountRecoveryPrompt) -> String {
        "The saved refresh token for \"\(prompt.accountName)\" is no longer valid. To fix this, remove the account from Codex Switcher, then add it again to regenerate the token. To avoid this issue in the future, do not use the \"Log out\" button in Codex."
    }
}

private struct AccountDetailsWindowForm: View {
    private enum ResetRow: Hashable {
        case sevenDay
        case fiveHour
    }

    let account: StoredAccount
    let controller: AppController

    @FocusState private var isNameFieldFocused: Bool
    @State private var draftName: String
    @State private var resetDisplayModes: [ResetRow: AccountDisplayFormatter.ResetTimeDisplayMode] = [
        .sevenDay: .relative,
        .fiveHour: .relative,
    ]

    init(account: StoredAccount, controller: AppController) {
        self.account = account
        self.controller = controller
        _draftName = State(initialValue: account.name)
    }

    var body: some View {
        Form {
            Section("Account") {
                nameRow
                iconRow

                LabeledContent("Last Login") {
                    LastLoginText(lastLoginAt: account.lastLoginAt)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Rate Limits") {
                LabeledContent("5-Hour Remaining") {
                    usageValueText(account.fiveHourLimitUsedPercent, isUnavailable: account.isUnavailable)
                }

                LabeledContent("5-Hour Reset") {
                    resetValueButton(account.fiveHourResetsAt, row: .fiveHour)
                }

                LabeledContent("7-Day Remaining") {
                    usageValueText(account.sevenDayLimitUsedPercent, isUnavailable: account.isUnavailable)
                }

                LabeledContent("7-Day Reset") {
                    resetValueButton(account.sevenDayResetsAt, row: .sevenDay)
                }
            }

            if account.isUnavailable {
                Section("Warning") {
                    Text(account.unavailableWarningMessage(accountName: displayName))
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(displayName)
        .onDisappear(perform: persistDraftName)
        .onChange(of: account.id) { _, _ in
            draftName = account.name
        }
        .onChange(of: account.name) { _, newName in
            guard !isNameFieldFocused else {
                return
            }

            draftName = newName
        }
    }

    private var nameRow: some View {
        LabeledContent("Name") {
            TextField(
                "",
                text: $draftName,
                prompt: Text(nameEditorPrompt)
            )
            .multilineTextAlignment(.trailing)
            .focused($isNameFieldFocused)
            .onSubmit(persistDraftName)
            .onChange(of: isNameFieldFocused) { _, isFocused in
                if !isFocused {
                    persistDraftName()
                }
            }
            .frame(maxWidth: 240, alignment: .trailing)
        }
    }

    private var iconRow: some View {
        LabeledContent("Icon") {
            Picker("", selection: selectedIconBinding) {
                ForEach(AccountIconOption.displayOrder) { icon in
                    Label(icon.title, systemImage: icon.systemName)
                        .tag(icon)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 220, alignment: .trailing)
        }
    }

    private var selectedIconBinding: Binding<AccountIconOption> {
        Binding(
            get: { selectedIcon },
            set: { newIcon in
                controller.setIcon(newIcon, for: account.id)
            }
        )
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

    private func usageValueText(_ value: Int?, isUnavailable: Bool) -> some View {
        Text(
            AccountDisplayFormatter.detailedPercentDescription(
                value,
                isUnavailable: isUnavailable
            )
        )
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func resetValueButton(_ value: Date?, row: ResetRow) -> some View {
        if value == nil {
            RateLimitResetText(
                resetAt: value,
                fallbackText: "Unavailable",
                displayMode: resetDisplayModes[row] ?? .relative
            )
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .accessibilityHint("Reset time unavailable")
        } else {
            Button {
                toggleResetDisplayMode(for: row)
            } label: {
                RateLimitResetText(
                    resetAt: value,
                    fallbackText: "Unavailable",
                    displayMode: resetDisplayModes[row] ?? .relative
                )
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Click to switch between relative and absolute time")
        }
    }

    private func toggleResetDisplayMode(for row: ResetRow) {
        let currentMode = resetDisplayModes[row] ?? .relative
        resetDisplayModes[row] = currentMode == .relative ? .absolute : .relative
    }

    private func persistDraftName() {
        guard !account.isDeleted else {
            return
        }

        guard draftName != account.name else {
            return
        }

        controller.commitRename(for: account.id, proposedName: draftName)
        draftName = account.name
    }
}
