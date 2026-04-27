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
                AccountDetailsWindowForm(account: selectedAccount, controller: controller)
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

    private struct SharePreparationKey: Equatable {
        let transferItemID: UUID
        let availabilityKey: String
        let exportContentKey: String
    }

    private struct PreparedShare: Equatable {
        let key: SharePreparationKey
        let file: PreparedCodexAccountArchiveFile
    }

    let account: StoredAccount
    let controller: AppController

    @FocusState private var isNameFieldFocused: Bool
    @FocusState private var isNotesEditorFocused: Bool
    @State private var draftName: String
    @State private var draftNotes: String
    @State private var resetDisplayModes: [ResetRow: AccountDisplayFormatter.ResetTimeDisplayMode] = [
        .sevenDay: .relative,
        .fiveHour: .relative,
    ]
    @State private var preparedShare: PreparedShare?
    @State private var isPreparingShare = false
    @State private var shareAvailability: Bool?
    @State private var pendingNotesSaveTask: Task<Void, Never>?

    init(account: StoredAccount, controller: AppController) {
        self.account = account
        self.controller = controller
        _draftName = State(initialValue: account.name)
        _draftNotes = State(initialValue: account.notes)
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

            Section("Notes") {
                notesEditor
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
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                loginToolbarItem
                shareToolbarItem
                pinToolbarItem
                removeToolbarItem
            }
        }
        .onDisappear(perform: persistDrafts)
        .task(id: sharePreparationKey) {
            let preparationKey = sharePreparationKey
            await prepareShareArchive(for: preparationKey, presentsErrors: false)
        }
        .onChange(of: account.id) { _, _ in
            draftName = account.name
            draftNotes = account.notes
        }
        .onChange(of: account.name) { _, newName in
            guard !isNameFieldFocused else {
                return
            }

            draftName = newName
        }
        .onChange(of: account.notes) { _, newNotes in
            guard !isNotesEditorFocused, draftNotes != newNotes else {
                return
            }

            draftNotes = newNotes
        }
        .onChange(of: draftNotes) { _, _ in
            scheduleDraftNotesSave()
        }
        .onChange(of: isNotesEditorFocused) { _, isFocused in
            if !isFocused {
                persistDraftNotes()
            }
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

    private var notesEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $draftNotes)
                .font(.body)
                .focused($isNotesEditorFocused)
                .frame(minHeight: 132)
                .accessibilityLabel("Account Notes")

            if draftNotes.isEmpty {
                Text("Add notes")
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
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

    private var sharePreparationKey: SharePreparationKey {
        let transferItem = shareTransferItem
        return SharePreparationKey(
            transferItemID: transferItem.id,
            availabilityKey: transferItem.availabilityKey,
            exportContentKey: transferItem.request.exportContentKey
        )
    }

    private var shareTransferItem: CodexAccountArchiveTransferItem {
        controller.archiveTransferItem(for: account)
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

    private var loginToolbarItem: some View {
        Button {
            persistDraftName()
            controller.login(accountID: account.id)
        } label: {
            Image(systemName: "key")
        }
        .accessibilityLabel("Log In")
        .help("Log In")
    }

    @ViewBuilder
    private var shareToolbarItem: some View {
        let preparationKey = sharePreparationKey

        if let preparedShare, preparedShare.key == preparationKey {
            ShareLink(item: preparedShare.file.fileURL, preview: SharePreview(displayName)) {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel("Share Account Archive")
            .help("Share Account Archive")
        } else if isPreparingShare || shareAvailability == nil {
            Button {
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .disabled(true)
            .accessibilityLabel("Share Account Archive")
            .help("Share Account Archive")
        } else {
            Button {
                Task { @MainActor in
                    let preparationKey = sharePreparationKey
                    await prepareShareArchive(for: preparationKey, presentsErrors: true)
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel("Share Account Archive")
            .help("Share Account Archive")
        }
    }

    private var pinToolbarItem: some View {
        Button {
            controller.setPinned(!account.isPinned, for: account.id)
        } label: {
            Image(systemName: account.isPinned ? "pin.slash" : "pin")
        }
        .accessibilityLabel(account.isPinned ? "Unpin Account" : "Pin Account")
        .help(account.isPinned ? "Unpin Account" : "Pin Account")
    }

    private var removeToolbarItem: some View {
        Button(role: .destructive) {
            controller.removeAccounts(withIDs: [account.id])
        } label: {
            Image(systemName: "trash")
        }
        .accessibilityLabel("Remove Account")
        .help("Remove Account")
    }

    @MainActor
    private func prepareShareArchive(
        for preparationKey: SharePreparationKey,
        presentsErrors: Bool
    ) async {
        guard !account.isDeleted else {
            preparedShare = nil
            shareAvailability = false
            isPreparingShare = false
            return
        }

        preparedShare = nil
        shareAvailability = nil
        isPreparingShare = true

        defer {
            if sharePreparationKey == preparationKey {
                isPreparingShare = false
            }
        }

        do {
            let preparedFile = try await controller.prepareArchiveFile(for: account)

            guard sharePreparationKey == preparationKey else {
                return
            }

            preparedShare = PreparedShare(key: preparationKey, file: preparedFile)
            shareAvailability = true
        } catch {
            guard sharePreparationKey == preparationKey else {
                return
            }

            preparedShare = nil
            shareAvailability = false

            if presentsErrors {
                controller.presentedAlert = UserFacingAlert(
                    title: "Couldn't Export Account",
                    message: sharePreparationErrorMessage(for: error)
                )
            }
        }
    }

    private func sharePreparationErrorMessage(for error: Error) -> String {
        if let snapshotError = error as? AccountSnapshotStoreError,
           snapshotError == .missingSnapshot {
            return "That saved account is not exportable on this device yet. If it was added on another device, open Codex Switcher there once after updating, then wait a moment for iCloud Keychain to sync or import its .cxa file here."
        }

        return error.localizedDescription
    }

    private func persistDrafts() {
        persistDraftName()
        persistDraftNotes()
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

    private func scheduleDraftNotesSave() {
        guard draftNotes != account.notes else {
            return
        }

        pendingNotesSaveTask?.cancel()
        pendingNotesSaveTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(700))
            } catch {
                return
            }

            persistDraftNotes(cancelsPendingSave: false)
            pendingNotesSaveTask = nil
        }
    }

    private func persistDraftNotes(cancelsPendingSave: Bool = true) {
        if cancelsPendingSave {
            pendingNotesSaveTask?.cancel()
            pendingNotesSaveTask = nil
        }

        guard !account.isDeleted else {
            return
        }

        guard draftNotes != account.notes else {
            return
        }

        controller.setNotes(draftNotes, for: account.id)
        draftNotes = account.notes
    }
}
