//
//  AccountDetailView.swift
//  Codex Switcher Watch App
//
//  Created by Marcel Kwiatkowski on 2026-04-12.
//

import SwiftData
import SwiftUI

struct WatchAccountDetailView: View {
    private enum ResetRow: Hashable {
        case fiveHour
        case sevenDay
    }

    private enum LiveRefreshStatus {
        case checking
        case available
        case waitingForCredential
        case unavailableForAPIKey
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.modelContext) private var modelContext

    let account: StoredAccount
    let refreshController: WatchRateLimitRefreshController
    let onError: (PresentedError) -> Void

    @FocusState private var isNotesEditorFocused: Bool
    @State private var draftName: String
    @State private var draftNotes: String
    @State private var liveRefreshStatus: LiveRefreshStatus = .checking
    @State private var resetDisplayModes: [ResetRow: AccountDisplayFormatter.ResetTimeDisplayMode] = [
        .fiveHour: .relative,
        .sevenDay: .relative,
    ]
    @State private var showingRemoveConfirmation = false
    @State private var pendingNotesSaveTask: Task<Void, Never>?

    init(
        account: StoredAccount,
        refreshController: WatchRateLimitRefreshController,
        onError: @escaping (PresentedError) -> Void
    ) {
        self.account = account
        self.refreshController = refreshController
        self.onError = onError
        _draftName = State(initialValue: account.name)
        _draftNotes = State(initialValue: account.notes)
    }

    var body: some View {
        Form {
            Section("Account") {
                NavigationLink {
                    WatchAccountNameEditorView(
                        draftName: $draftName,
                        placeholder: normalized(account.emailHint) ?? "",
                        onSave: persistDraftName
                    )
                } label: {
                    LabeledContent("Name") {
                        Text(displayName)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .multilineTextAlignment(.trailing)
                    }
                }

                NavigationLink {
                    WatchAccountIconPickerView(account: account, onError: onError)
                } label: {
                    LabeledContent("Icon") {
                        Image(systemName: selectedIcon.systemName)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(selectedIcon.title)
                    }
                }

                LabeledContent("Last Login") {
                    LastLoginText(lastLoginAt: account.lastLoginAt)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                LabeledContent("5-Hour Remaining") {
                    usageValueText(account.fiveHourLimitUsedPercent, isUnavailable: account.isUnavailable)
                }

                LabeledContent("5-Hour Reset") {
                    resetValueButton(account.fiveHourResetsAt, row: .fiveHour, isUnavailable: account.isUnavailable)
                }

                LabeledContent("7-Day Remaining") {
                    usageValueText(account.sevenDayLimitUsedPercent, isUnavailable: account.isUnavailable)
                }

                LabeledContent("7-Day Reset") {
                    resetValueButton(account.sevenDayResetsAt, row: .sevenDay, isUnavailable: account.isUnavailable)
                }
            } header: {
                Text("Rate Limits")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    switch liveRefreshStatus {
                    case .waitingForCredential:
                        Text("Waiting for iCloud Keychain to sync this account.")
                    case .unavailableForAPIKey:
                        Text("Live refresh isn't available for API-key accounts.")
                    case .checking, .available:
                        EmptyView()
                    }
                }
                .opacity(isLuminanceReduced ? 0.72 : 1)
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
        .refreshable {
            await refreshController.refreshNowAndWait(for: account.identityKey)
            await updateLiveRefreshAvailability()
        }
        .task(id: account.identityKey) {
            await updateLiveRefreshAvailability()
            refreshController.setSelected(identityKey: account.identityKey)
            WidgetSnapshotPublisher.publish(
                modelContext: modelContext,
                selectedAccountID: account.identityKey,
                selectedAccountIsLive: true
            )
        }
        .confirmationDialog(
            "Remove \"\(displayName)\"?",
            isPresented: $showingRemoveConfirmation
        ) {
            Button("Remove", role: .destructive) {
                dismissAndRemoveAccount()
            }
        } message: {
            Text("Are you sure you want to remove this account from Codex switcher? You will be able to add it again later.")
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingRemoveConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Account actions")
            }
        }
    }

    private var displayName: String {
        AccountsPresentationLogic.displayName(
            name: draftName,
            emailHint: account.emailHint,
            accountIdentifier: account.accountIdentifier,
            identityKey: account.identityKey
        )
    }

    private var selectedIcon: AccountIconOption {
        AccountIconOption.resolve(from: account.iconSystemName)
    }

    private var notesEditor: some View {
        TextField("Add notes", text: $draftNotes, axis: .vertical)
            .focused($isNotesEditorFocused)
            .lineLimit(4...8)
            .accessibilityLabel("Account Notes")
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
    private func resetValueButton(_ value: Date?, row: ResetRow, isUnavailable: Bool) -> some View {
        let displayedValue = isUnavailable ? nil : value

        if displayedValue == nil {
            RateLimitResetText(
                resetAt: displayedValue,
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
                    resetAt: displayedValue,
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

    private func persistDrafts() {
        persistDraftName()
        persistDraftNotes()
    }

    private func persistDraftName() {
        guard !account.isDeleted else {
            return
        }

        do {
            try StoredAccountMutations.rename(account, to: draftName, in: modelContext)
            draftName = account.name
        } catch {
            onError(
                PresentedError(
                    title: "Couldn't Rename Account",
                    message: error.localizedDescription
                )
            )
        }
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

        do {
            try StoredAccountMutations.setNotes(draftNotes, for: account, in: modelContext)
            draftNotes = account.notes
        } catch {
            onError(
                PresentedError(
                    title: "Couldn't Save Notes",
                    message: error.localizedDescription
                )
            )
        }
    }

    private func updateLiveRefreshAvailability() async {
        if CodexAuthMode(rawValue: account.authModeRaw) == .apiKey {
            liveRefreshStatus = .unavailableForAPIKey
            return
        }

        liveRefreshStatus = await refreshController.hasSyncedCredential(for: account.identityKey)
            ? .available
            : .waitingForCredential
    }

    private func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func dismissAndRemoveAccount() {
        dismiss()

        Task { @MainActor in
            // Pop the current watch navigation destination before deleting the
            // backing model so SwiftUI doesn't leave the user on a dead detail
            // route for one transition frame.
            await Task.yield()

            do {
                try await StoredAccountMutations.remove(account, in: modelContext)
            } catch {
                onError(
                    PresentedError(
                        title: "Couldn't Remove Account",
                        message: error.localizedDescription
                    )
                )
            }
        }
    }
}

#Preview("Account Detail") {
    let container = WatchPreviewData.makeContainer()
    let descriptor = FetchDescriptor<StoredAccount>()
    let account = try! container.mainContext.fetch(descriptor).first!

    return NavigationStack {
        WatchAccountDetailView(
            account: account,
            refreshController: WatchRateLimitRefreshController(),
            onError: { _ in }
        )
    }
    .modelContainer(container)
}

#Preview("Missing Limits") {
    let container = WatchPreviewData.makeContainer()
    let descriptor = FetchDescriptor<StoredAccount>()
    let account = try! container.mainContext.fetch(descriptor).last!

    return NavigationStack {
        WatchAccountDetailView(
            account: account,
            refreshController: WatchRateLimitRefreshController(),
            onError: { _ in }
        )
    }
    .modelContainer(container)
}

#Preview("Reduced Luminance") {
    let container = WatchPreviewData.makeContainer()
    let descriptor = FetchDescriptor<StoredAccount>()
    let account = try! container.mainContext.fetch(descriptor).first!

    return NavigationStack {
        WatchAccountDetailView(
            account: account,
            refreshController: WatchRateLimitRefreshController(),
            onError: { _ in }
        )
    }
    .modelContainer(container)
    .environment(\.isLuminanceReduced, true)
}
