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

    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @Query private var accounts: [StoredAccount]

    private var displayedAccounts: [StoredAccount] {
        controller.displayedAccounts(from: accounts)
    }

    private var accountListHeight: CGFloat {
        let rowHeight: CGFloat = 46
        let visibleRows = min(max(displayedAccounts.count, 1), 6)
        return CGFloat(visibleRows) * rowHeight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if controller.shouldShowAuthStatusBanner {
                statusCard
            }

            accountSection

            Divider()

            footer
        }
        .padding(14)
        .frame(width: 360)
        .fileImporter(
            isPresented: $controller.isShowingLocationPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false,
            onCompletion: controller.handleLocationImport
        )
        .fileDialogCustomizationID("codex-auth-location")
        .fileDialogDefaultDirectory(FileManager.default.homeDirectoryForCurrentUser)
        .fileDialogBrowserOptions([.includeHiddenFiles])
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
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

            Button {
                openMainWindow()
            } label: {
                Image(systemName: "rectangle.on.rectangle")
            }
            .buttonStyle(.plain)
            .help("Open the main window")
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
            .frame(maxWidth: .infinity)
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

                                    if let subtitle = account.emailHint ?? account.accountIdentifier {
                                        Text(subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
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
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(height: min(accountListHeight, 300))
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button("Add Account") {
                    controller.captureCurrentAccount()
                }
                .disabled(controller.isSwitching)

                Button("Refresh") {
                    controller.refresh()
                }
            }

            HStack {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }

                Spacer()

                Button("Quit") {
                    NSApp.terminate(nil)
                }
            }
            .font(.subheadline)
        }
    }

    private func openMainWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
        dismiss()
    }
}
