//
//  MenuBarAccountsView.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-08.
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

    private var displayedAccounts: [StoredAccount] {
        controller.displayedAccounts(from: accounts)
    }

    private var accountListHeight: CGFloat {
        let rowHeight: CGFloat = 46
        let visibleRows = min(max(displayedAccounts.count, 1), 14)
        return CGFloat(visibleRows) * rowHeight
    }

    private var accountSectionHeight: CGFloat {
        displayedAccounts.isEmpty ? 180 : min(accountListHeight, 640)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if controller.shouldShowAuthStatusBanner {
                statusCard
            }

            accountSection
        }
        .padding(14)
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
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
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

            HStack(spacing: 10) {
                chromeButton(
                    systemImage: "plus",
                    helpText: "Add Account",
                    isDisabled: controller.isSwitching,
                    action: controller.captureCurrentAccount
                )
                chromeButton(systemImage: "rectangle.on.rectangle", helpText: "Open App", action: openMainWindow)
                chromeButton(systemImage: "rectangle.portrait.and.arrow.right", helpText: "Quit", action: quitApp)
            }
        }
    }

    private var statusCard: some View {
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
        .padding(10)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var accountSection: some View {
        if displayedAccounts.isEmpty {
            ContentUnavailableView(
                "No Accounts",
                systemImage: "person.crop.rectangle.stack",
                description: Text("Add the currently used account from the menu bar or the main window.")
            )
            .frame(maxWidth: .infinity, minHeight: accountSectionHeight)
        } else {
            ScrollView {
                // MenuBarExtra window scenes can reserve space for lazy stacks
                // before they materialize children, which leaves a blank region
                // instead of visible rows. Use an eager stack plus an explicit
                // scroll height so the account list renders reliably here.
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(displayedAccounts) { account in
                        Button {
                            controller.login(accountID: account.id)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: account.iconSystemName)
                                    .frame(width: 18)
                                    .foregroundStyle(.primary)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(account.name)
                                        .lineLimit(1)

                                    AccountMetadataText(
                                        lastLoginAt: account.lastLoginAt,
                                        sevenDayLimitUsedPercent: account.sevenDayLimitUsedPercent,
                                        fiveHourLimitUsedPercent: account.fiveHourLimitUsedPercent,
                                        font: .caption
                                    )
                                }

                                Spacer(minLength: 12)

                                if account.identityKey == controller.activeIdentityKey {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(
                                    account.identityKey == controller.activeIdentityKey
                                    ? Color.primary.opacity(0.08)
                                    : .clear
                                )
                        )
                        .disabled(controller.isSwitching)
                        .onAppear {
                            controller.setRateLimitVisibility(true, for: account.identityKey)
                        }
                        .onDisappear {
                            controller.setRateLimitVisibility(false, for: account.identityKey)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(height: accountSectionHeight)
        }
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
        .accessibilityLabel(helpText)
    }
}
