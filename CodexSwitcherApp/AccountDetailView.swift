//
//  AccountDetailView.swift
//  Codex Switcher
//
//  Created by Marcel Kwiatkowski on 2026-04-11.
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

    private struct SharePreparationKey: Equatable {
        let transferItemID: UUID
        let exportContentKey: String
        let refreshToken: Int
    }

    private struct PreparedShare: Equatable {
        let key: SharePreparationKey
        let file: PreparedCodexAccountArchiveFile
    }

    @Environment(\.modelContext) private var modelContext

    let account: StoredAccount
    let controller: IOSAccountsController
    let onRemove: () -> Void

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

    init(
        account: StoredAccount,
        controller: IOSAccountsController,
        onRemove: @escaping () -> Void
    ) {
        self.account = account
        self.controller = controller
        self.onRemove = onRemove
        _draftName = State(initialValue: account.name)
        _draftNotes = State(initialValue: account.notes)
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
                    LastLoginText(lastLoginAt: account.lastLoginAt)
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

            Section("Notes") {
                notesEditor
            }

            if account.isUnavailable {
                Section("Warning") {
                    Text(account.unavailableWarningMessage(accountName: displayName))
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                shareToolbarItem
            }

            ToolbarItem(placement: .topBarTrailing) {
                detailMenu
            }
        }
        .navigationDestination(for: DetailDestination.self, destination: destinationView)
        .onDisappear(perform: persistDrafts)
        .onChange(of: draftNotes) { _, _ in
            scheduleDraftNotesSave()
        }
        .onChange(of: account.notes) { _, newNotes in
            guard !isNotesEditorFocused, draftNotes != newNotes else {
                return
            }

            draftNotes = newNotes
        }
        .onChange(of: isNotesEditorFocused) { _, isFocused in
            if !isFocused {
                persistDraftNotes()
            }
        }
        .task(id: sharePreparationKey) {
            let preparationKey = sharePreparationKey
            await prepareShareArchive(for: preparationKey, presentsErrors: false)
        }
    }

    private var notesEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $draftNotes)
                .focused($isNotesEditorFocused)
                .frame(minHeight: 128)
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
            exportContentKey: transferItem.request.exportContentKey,
            refreshToken: controller.archiveAvailabilityRefreshToken
        )
    }

    private var shareTransferItem: CodexAccountArchiveTransferItem {
        controller.archiveTransferItem(for: account)
    }

    private func usageValueText(_ value: Int?, isUnavailable: Bool) -> some View {
        let description = AccountDisplayFormatter.detailedPercentDescription(
            value,
            isUnavailable: isUnavailable
        )

        return Text(description)
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
            .accessibilityHint("Double tap to switch between relative and absolute time")
        }
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

    private func persistDrafts() {
        persistDraftName()
        persistDraftNotes()
    }

    private func persistDraftName() {
        guard !account.isDeleted else {
            return
        }

        controller.commitRename(for: account, proposedName: draftName, in: modelContext)
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

        controller.setNotes(draftNotes, for: account, in: modelContext)
        draftNotes = account.notes
    }

    @ViewBuilder
    private var shareToolbarItem: some View {
        let preparationKey = sharePreparationKey

        if let preparedShare, preparedShare.key == preparationKey {
            ShareLink(item: preparedShare.file.fileURL, preview: SharePreview(displayName)) {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel("Share Account Archive")
        } else if isPreparingShare || shareAvailability == nil {
            Button {
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .disabled(true)
            .accessibilityLabel("Share Account Archive")
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
        }
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
                controller.presentedError = PresentedError(
                    title: "Couldn't Export Account",
                    message: sharePreparationErrorMessage(for: error)
                )
            }
        }
    }

    private func sharePreparationErrorMessage(for error: Error) -> String {
        if let snapshotError = error as? AccountSnapshotStoreError,
           snapshotError == .missingSnapshot {
            return "That saved account isn't exportable on this device yet. If it was added on another device, open Codex Switcher there once after updating, then wait a moment for iCloud Keychain to sync or import its .cxa file here."
        }

        return error.localizedDescription
    }

    private var detailMenu: some View {
        Menu {
            Button {
                controller.setPinned(!account.isPinned, for: account, in: modelContext)
            } label: {
                Label(
                    account.isPinned ? "Unpin" : "Pin",
                    systemImage: account.isPinned ? "pin.slash" : "pin"
                )
            }

            Button(role: .destructive, action: onRemove) {
                Label("Remove", systemImage: "trash")
                    .foregroundStyle(.red)
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("Account Actions")
    }
}
