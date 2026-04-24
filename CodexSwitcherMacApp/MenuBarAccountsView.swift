//
//  MenuBarAccountsView.swift
//  Codex Switcher Mac App
//
//  Created by Marcel Kwiatkowski on 2026-04-08.
//

import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct MenuBarAccountsView: View {
    @Bindable var controller: AppController

    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @Query private var accounts: [StoredAccount]
    @State private var measuredAccountListContentHeight: CGFloat = 0

    private static let maxVisibleAccountRows = 5
    private static let accountRowSpacing: CGFloat = 2
    private static let accountSectionBottomInset: CGFloat = 4
    private static let fallbackRowHeight: CGFloat = 58

    private var displayedAccounts: [StoredAccount] {
        controller.displayedAccounts(from: accounts)
    }

    private var accountListHeight: CGFloat {
        // Derive the panel height from the rendered list content so future row
        // design changes do not leave the menu clipped or padded incorrectly.
        let rowCount = max(displayedAccounts.count, 1)
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
        displayedAccounts.isEmpty ? 180 : accountListHeight
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
        .fileImporter(
            isPresented: $controller.isShowingLocationPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false,
            onCompletion: controller.handleLocationImport
        )
        .fileDialogCustomizationID("codex-auth-location")
        .fileDialogDefaultDirectory(FileManager.default.homeDirectoryForCurrentUser)
        .fileDialogBrowserOptions([.includeHiddenFiles])
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
        if displayedAccounts.isEmpty {
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
                    ForEach(displayedAccounts) { account in
                        let isCurrentAccount = account.identityKey == controller.activeIdentityKey
                        Button {
                            controller.login(accountID: account.id)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: account.iconSystemName)
                                    .font(.title3)
                                    .frame(width: 24, height: 24)
                                    .foregroundStyle(.secondary)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(account.name)
                                        .font(.callout.weight(.semibold))
                                        .lineLimit(1)

                                    AccountMetadataText(
                                        lastLoginAt: account.lastLoginAt,
                                        sevenDayLimitUsedPercent: account.sevenDayLimitUsedPercent,
                                        fiveHourLimitUsedPercent: account.fiveHourLimitUsedPercent,
                                        sevenDayResetsAt: account.sevenDayResetsAt,
                                        fiveHourResetsAt: account.fiveHourResetsAt,
                                        font: .caption
                                    )
                                }

                                Spacer(minLength: 8)

                                Group {
                                    if isCurrentAccount {
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
                                if isCurrentAccount {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(currentAccountBackground)
                                }
                            }
                            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(controller.isSwitching)
                        .onAppear {
                            controller.setRateLimitVisibility(true, for: account.identityKey)
                        }
                        .onDisappear {
                            controller.setRateLimitVisibility(false, for: account.identityKey)
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
