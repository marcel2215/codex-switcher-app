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
                    title: "5-Hour Remaining",
                    remainingPercent: account.fiveHourLimitUsedPercent,
                    resetsAt: account.fiveHourResetsAt,
                    dimSecondaryContent: isLuminanceReduced
                )

                WatchRateLimitCard(
                    title: "7-Day Remaining",
                    remainingPercent: account.sevenDayLimitUsedPercent,
                    resetsAt: account.sevenDayResetsAt,
                    dimSecondaryContent: isLuminanceReduced
                )
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if let observedAt = account.rateLimitsObservedAt {
                        Text("Updated \(observedAt, style: .relative)")
                    }

                    switch liveRefreshStatus {
                    case .waitingForCredential:
                        Text("Waiting for iCloud Keychain to sync this account.")
                    case .unavailableForAPIKey:
                        Text("Live refresh isn't available for API-key accounts.")
                    case .checking, .available:
                        EmptyView()
                    }
                }
            }

            Section("Account") {
                if let emailHint = normalized(account.emailHint) {
                    WatchMetadataRow(title: "Email", value: emailHint, isSensitive: true)
                }

                if let accountID = normalized(account.accountIdentifier) {
                    WatchMetadataRow(title: "ID", value: accountID, isSensitive: true)
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
            await refreshController.refreshNowAndWait(for: account.identityKey)
            await updateLiveRefreshAvailability()
        }
        .task(id: account.identityKey) {
            await updateLiveRefreshAvailability()
            refreshController.setSelected(identityKey: account.identityKey)
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
}

private struct WatchMetadataRow: View {
    let title: String
    let value: String
    let isSensitive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if isSensitive {
                Text(value)
                    .font(.footnote)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .privacySensitive()
            } else {
                Text(value)
                    .font(.footnote)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
        }
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
            }

            if let percent = AccountDisplayFormatter.clampedPercentValue(remainingPercent) {
                Gauge(value: Double(percent), in: 0...100) {
                    EmptyView()
                }
            } else {
                Text("Not available yet")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
