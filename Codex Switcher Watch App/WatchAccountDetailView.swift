//
//  WatchAccountDetailView.swift
//  Codex Switcher Watch App
//
//  Created by Codex on 2026-04-12.
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

    @State private var draftName: String
    @State private var liveRefreshStatus: LiveRefreshStatus = .checking
    @State private var resetDisplayModes: [ResetRow: AccountDisplayFormatter.ResetTimeDisplayMode] = [
        .fiveHour: .relative,
        .sevenDay: .relative,
    ]
    @State private var showingRemoveConfirmation = false

    init(
        account: StoredAccount,
        refreshController: WatchRateLimitRefreshController,
        onError: @escaping (PresentedError) -> Void
    ) {
        self.account = account
        self.refreshController = refreshController
        self.onError = onError
        _draftName = State(initialValue: account.name)
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
                    Text(AccountDisplayFormatter.lastLoginValueDescription(from: account.lastLoginAt))
                        .foregroundStyle(.secondary)
                }
            }

            Section {
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

            Section {
                Button("Remove Account", role: .destructive) {
                    showingRemoveConfirmation = true
                }
            } header: {
                Text("Danger Zone")
            }
        }
        .navigationTitle(displayName)
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
            "Remove this account?",
            isPresented: $showingRemoveConfirmation
        ) {
            Button("Remove", role: .destructive) {
                dismissAndRemoveAccount()
            }
        } message: {
            Text("You can add it again later from the Mac.")
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

    private func usageValueText(_ value: Int?) -> some View {
        Text(AccountDisplayFormatter.detailedPercentDescription(value))
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
                try StoredAccountMutations.remove(account, in: modelContext)
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
