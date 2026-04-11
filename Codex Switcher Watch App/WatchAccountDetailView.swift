//
//  WatchAccountDetailView.swift
//  Codex Switcher Watch App
//
//  Created by Codex on 2026-04-12.
//

import SwiftData
import SwiftUI

struct WatchAccountDetailView: View {
    private enum LiveRefreshStatus {
        case checking
        case available
        case unavailable
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.modelContext) private var modelContext

    let account: StoredAccount
    let refreshController: WatchRateLimitRefreshController
    let onError: (PresentedError) -> Void

    @State private var draftName: String
    @State private var liveRefreshStatus: LiveRefreshStatus = .checking
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
        List {
            Section {
                WatchRateLimitCard(
                    title: "7-Day Remaining",
                    remainingPercent: account.sevenDayLimitUsedPercent,
                    resetsAt: account.sevenDayResetsAt,
                    dimSecondaryContent: isLuminanceReduced
                )

                WatchRateLimitCard(
                    title: "5-Hour Remaining",
                    remainingPercent: account.fiveHourLimitUsedPercent,
                    resetsAt: account.fiveHourResetsAt,
                    dimSecondaryContent: isLuminanceReduced
                )
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if let observedAt = account.rateLimitsObservedAt {
                        Text("Updated \(observedAt, style: .relative)")
                            .privacySensitive()
                    }

                    if liveRefreshStatus == .unavailable {
                        Text("Live refresh unavailable on this watch yet.")
                    }
                }
            }

            Section("Account") {
                if let emailHint = normalized(account.emailHint) {
                    LabeledContent("Email") {
                        Text(emailHint)
                            .privacySensitive()
                    }
                }

                if let accountID = normalized(account.accountIdentifier) {
                    LabeledContent("ID") {
                        Text(accountID)
                            .privacySensitive()
                    }
                }

                LabeledContent("Last Login") {
                    Text(AccountDisplayFormatter.lastLoginValueDescription(from: account.lastLoginAt))
                }
            }

            Section("Edit") {
                NavigationLink("Name") {
                    WatchAccountNameEditorView(
                        draftName: $draftName,
                        placeholder: normalized(account.emailHint) ?? "",
                        onSave: persistDraftName
                    )
                }

                NavigationLink("Icon") {
                    WatchAccountIconPickerView(account: account, onError: onError)
                }
            }

            Section {
                Button("Remove Account", role: .destructive) {
                    showingRemoveConfirmation = true
                }
            }
        }
        .navigationTitle(displayName)
        .refreshable {
            await refreshController.refreshTrackedAccountsNow()
            await updateLiveRefreshAvailability()
        }
        .task(id: account.identityKey) {
            await updateLiveRefreshAvailability()
            refreshController.setSelected(identityKey: account.identityKey)
            refreshController.refreshNow(for: account.identityKey)
        }
        .onDisappear {
            refreshController.setSelected(identityKey: nil)
            persistDraftName()
        }
        .confirmationDialog(
            "Remove this account?",
            isPresented: $showingRemoveConfirmation
        ) {
            Button("Remove", role: .destructive) {
                do {
                    try StoredAccountMutations.remove(account, in: modelContext)
                    dismiss()
                } catch {
                    onError(
                        PresentedError(
                            title: "Couldn't Remove Account",
                            message: error.localizedDescription
                        )
                    )
                }
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
        liveRefreshStatus = await refreshController.hasSyncedCredential(for: account.identityKey)
            ? .available
            : .unavailable
    }

    private func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct WatchRateLimitCard: View {
    let title: String
    let remainingPercent: Int?
    let resetsAt: Date?
    let dimSecondaryContent: Bool

    var body: some View {
        let now = Date()

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)

                Spacer()

                Text(AccountDisplayFormatter.compactPercentDescription(remainingPercent))
                    .font(.headline.monospacedDigit())
                    .privacySensitive()
            }

            Gauge(value: Double(AccountDisplayFormatter.clampedPercentValue(remainingPercent) ?? 0), in: 0...100) {
                EmptyView()
            }

            if let resetsAt, resetsAt > now {
                Text("Resets \(resetsAt, style: .relative)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .opacity(dimSecondaryContent ? 0.65 : 1)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
