//
//  MenuBarAccountsView.swift
//  Codex Switcher Mac App
//
//  Created by Marcel Kwiatkowski on 2026-04-08.
//

import AppKit
import SwiftData
import SwiftUI

struct MenuBarAccountsView: View {
    @Bindable var controller: AppController

    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @AppStorage(
        CodexSharedPreferenceKey.showNoneAccount,
        store: CodexSharedPreferences.userDefaults
    ) private var showNoneAccount = CodexSharedPreferenceDefaults.showNoneAccount
    @Query private var accounts: [StoredAccount]
    @State private var measuredAccountListContentHeight: CGFloat = 0

    private static let maxVisibleAccountRows = 5
    private static let accountRowSpacing: CGFloat = 2
    private static let accountSectionBottomInset: CGFloat = 4
    private static let fallbackRowHeight: CGFloat = 58

    private var displayedAccounts: [StoredAccount] {
        controller.displayedAccounts(from: accounts)
    }

    private var displayedAccountRows: [MenuBarAccountRowItem] {
        let accountRows = displayedAccounts.map { account in
            MenuBarAccountRowItem(
                account: account,
                isCurrentAccount: account.identityKey == controller.activeIdentityKey
            )
        }

        guard showNoneAccount else {
            return accountRows
        }

        return [MenuBarAccountRowItem.none(isCurrentAccount: controller.activeIdentityKey == nil)] + accountRows
    }

    private var accountListHeight: CGFloat {
        // Derive the panel height from the rendered list content so future row
        // design changes do not leave the menu clipped or padded incorrectly.
        let rowCount = max(displayedAccountRows.count, 1)
        let totalMeasuredSpacing = CGFloat(max(rowCount - 1, 0)) * Self.accountRowSpacing
        let measuredRowHeight = if measuredAccountListContentHeight > totalMeasuredSpacing {
            (measuredAccountListContentHeight - totalMeasuredSpacing) / CGFloat(rowCount)
        } else {
            Self.fallbackRowHeight
        }

        let visibleRows = min(rowCount, Self.maxVisibleAccountRows)
        let visibleSpacing = CGFloat(max(visibleRows - 1, 0)) * Self.accountRowSpacing
        return (CGFloat(visibleRows) * measuredRowHeight) + visibleSpacing + Self.accountSectionBottomInset
    }

    private var accountSectionHeight: CGFloat {
        displayedAccountRows.isEmpty ? 180 : accountListHeight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if controller.shouldShowAuthStatusBanner {
                statusCard
            }

            accountSection
        }
        .padding(10)
        // Let the row list determine the natural content height so short menus
        // don't keep a stale fixed panel size with empty space at the bottom.
        .frame(width: 360, alignment: .top)
        .task {
            controller.configure(modelContext: modelContext, undoManager: nil)
        }
        .onAppear {
            controller.setMenuBarPresented(true)
        }
        .onDisappear {
            controller.setMenuBarPresented(false)
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
                primaryButton: .destructive(Text("Remove Account")) {
                    controller.removeUnavailableAccountFromPrompt(prompt)
                },
                secondaryButton: .cancel(Text("Keep")) {
                    controller.keepUnavailableAccountFromPrompt()
                }
            )
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Codex Switcher")
                    .font(.headline)

                if let currentAccount = displayedAccounts.first(where: { $0.identityKey == controller.activeIdentityKey }) {
                    Text("Current: \(currentAccount.name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if case .missingAuthFile = controller.authAccessState {
                    Text("Codex is currently logged out")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                chromeButton(
                    systemImage: "plus",
                    helpText: controller.captureCurrentAccountHelpText,
                    accessibilityLabel: "Add Account",
                    isDisabled: !controller.canCaptureCurrentAccount,
                    action: controller.captureCurrentAccount
                )
                chromeButton(systemImage: "rectangle.on.rectangle", helpText: "Open App", action: openMainWindow)
                chromeButton(systemImage: "rectangle.portrait.and.arrow.right", helpText: "Quit", action: quitApp)
            }
        }
    }

    private var statusCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label(controller.authAccessState.title, systemImage: controller.authAccessState.systemImage)
                    .font(.subheadline.weight(.semibold))

                Text(controller.authAccessState.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(controller.linkButtonTitle) {
                    controller.beginLinkingCodexLocation()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var accountSection: some View {
        if displayedAccountRows.isEmpty {
            ContentUnavailableView(
                "No Accounts",
                systemImage: "person.crop.rectangle.stack",
                description: Text(emptyAccountDescription)
            )
            .frame(maxWidth: .infinity, minHeight: accountSectionHeight)
        } else {
            ScrollView {
                // MenuBarExtra window scenes can reserve space for lazy stacks
                // before they materialize children, which leaves a blank region
                // instead of visible rows. Use an eager stack plus an explicit
                // scroll height so the account list renders reliably here.
                VStack(alignment: .leading, spacing: Self.accountRowSpacing) {
                    ForEach(displayedAccountRows) { item in
                        Button {
                            controller.login(accountID: item.id)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: item.iconSystemName)
                                    .font(.title3)
                                    .frame(width: 24, height: 24)
                                    .foregroundStyle(.secondary)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.displayName)
                                        .font(.callout.weight(.semibold))
                                        .lineLimit(1)

                                    AccountMetadataText(
                                        lastLoginAt: item.lastLoginAt,
                                        sevenDayLimitUsedPercent: item.sevenDayLimitUsedPercent,
                                        fiveHourLimitUsedPercent: item.fiveHourLimitUsedPercent,
                                        sevenDayResetsAt: item.sevenDayResetsAt,
                                        fiveHourResetsAt: item.fiveHourResetsAt,
                                        font: .caption
                                    )
                                }

                                Spacer(minLength: 8)

                                Group {
                                    if item.isUnavailable {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundStyle(.orange)
                                            .help("This saved Codex account is unavailable.")
                                    } else if item.isCurrentAccount {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.accent)
                                    } else {
                                        Color.clear
                                    }
                                }
                                .frame(width: 16, height: 16)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background {
                                if item.isCurrentAccount {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(currentAccountBackground)
                                }
                            }
                            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(controller.isSwitching)
                        .onAppear {
                            if let identityKey = item.identityKey {
                                controller.setRateLimitVisibility(true, for: identityKey)
                            }
                        }
                        .onDisappear {
                            if let identityKey = item.identityKey {
                                controller.setRateLimitVisibility(false, for: identityKey)
                            }
                        }
                    }
                }
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: AccountListHeightPreferenceKey.self,
                            value: proxy.size.height
                        )
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(height: accountSectionHeight)
            .onPreferenceChange(AccountListHeightPreferenceKey.self) { newHeight in
                guard newHeight > 0, abs(newHeight - measuredAccountListContentHeight) > 0.5 else {
                    return
                }
                measuredAccountListContentHeight = newHeight
            }
        }
    }

    private var currentAccountBackground: Color {
        Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
    }

    private var emptyAccountDescription: String {
        controller.canCaptureCurrentAccount
            ? "Add the currently used account from the menu bar or the main window."
            : controller.captureCurrentAccountHelpText
    }

    private func unavailableAccountMessage(for prompt: UnavailableAccountRecoveryPrompt) -> String {
        """
        The saved Codex auth snapshot for "\(prompt.accountName)" is no longer accepted. It may have expired, been revoked, or been invalidated by a Codex logout.

        Do not use the Log out button in the Codex app to fix this. Codex logout can revoke managed ChatGPT tokens. To use this account again, keep it here, select None to locally clear auth.json, sign in again, then press + to capture a fresh snapshot.

        Would you like to remove this account from Codex Switcher or keep it?
        """
    }

    private func openMainWindow() {
        NSApp.setActivationPolicy(.regular)
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
        dismiss()
    }

    private func quitApp() {
        NSApp.terminate(nil)
    }

    @ViewBuilder
    private func chromeButton(
        systemImage: String,
        helpText: String,
        accessibilityLabel: String? = nil,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(helpText)
        .accessibilityLabel(accessibilityLabel ?? helpText)
    }
}

private struct AccountListHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct MenuBarAccountRowItem: Identifiable, Hashable {
    let id: UUID
    let identityKey: String?
    let displayName: String
    let iconSystemName: String
    let lastLoginAt: Date?
    let sevenDayLimitUsedPercent: Int?
    let fiveHourLimitUsedPercent: Int?
    let sevenDayResetsAt: Date?
    let fiveHourResetsAt: Date?
    let isCurrentAccount: Bool
    let isUnavailable: Bool

    init(account: StoredAccount, isCurrentAccount: Bool) {
        id = account.id
        identityKey = account.identityKey
        let resolvedName = AccountsPresentationLogic.displayName(for: account)
        displayName = account.isUnavailable ? "\(resolvedName) (Unavailable)" : resolvedName
        iconSystemName = AccountIconOption.resolve(from: account.iconSystemName).systemName
        lastLoginAt = account.lastLoginAt
        sevenDayLimitUsedPercent = account.isUnavailable ? 0 : account.sevenDayLimitUsedPercent
        fiveHourLimitUsedPercent = account.isUnavailable ? 0 : account.fiveHourLimitUsedPercent
        sevenDayResetsAt = account.isUnavailable ? nil : account.sevenDayResetsAt
        fiveHourResetsAt = account.isUnavailable ? nil : account.fiveHourResetsAt
        self.isCurrentAccount = isCurrentAccount
        isUnavailable = account.isUnavailable
    }

    static func none(isCurrentAccount: Bool) -> MenuBarAccountRowItem {
        MenuBarAccountRowItem(
            id: AppController.noneAccountSelectionID,
            identityKey: nil,
            displayName: "None",
            iconSystemName: "power",
            lastLoginAt: nil,
            sevenDayLimitUsedPercent: 0,
            fiveHourLimitUsedPercent: 0,
            sevenDayResetsAt: nil,
            fiveHourResetsAt: nil,
            isCurrentAccount: isCurrentAccount,
            isUnavailable: false
        )
    }

    private init(
        id: UUID,
        identityKey: String?,
        displayName: String,
        iconSystemName: String,
        lastLoginAt: Date?,
        sevenDayLimitUsedPercent: Int?,
        fiveHourLimitUsedPercent: Int?,
        sevenDayResetsAt: Date?,
        fiveHourResetsAt: Date?,
        isCurrentAccount: Bool,
        isUnavailable: Bool
    ) {
        self.id = id
        self.identityKey = identityKey
        self.displayName = displayName
        self.iconSystemName = iconSystemName
        self.lastLoginAt = lastLoginAt
        self.sevenDayLimitUsedPercent = sevenDayLimitUsedPercent
        self.fiveHourLimitUsedPercent = fiveHourLimitUsedPercent
        self.sevenDayResetsAt = sevenDayResetsAt
        self.fiveHourResetsAt = fiveHourResetsAt
        self.isCurrentAccount = isCurrentAccount
        self.isUnavailable = isUnavailable
    }
}
