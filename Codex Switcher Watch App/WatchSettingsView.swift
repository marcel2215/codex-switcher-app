//
//  WatchSettingsView.swift
//  Codex Switcher Watch App
//
//  Created by Codex on 2026-04-12.
//

import SwiftUI
import SwiftData

struct WatchSettingsView: View {
    private struct PresentedSettingsAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(ModelUndoController.self) private var modelUndoController
    @Query private var accounts: [StoredAccount]
    @State private var showingRemoveAllConfirmation = false
    @State private var presentedSettingsAlert: PresentedSettingsAlert?

    var body: some View {
        Form {
            Section("About") {
                LabeledContent("Version") {
                    Text(AppAboutInfo.current.formattedVersion)
                }
            }

            Section("History") {
                Button {
                    modelUndoController.undo()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(!modelUndoController.canUndo)

                Button {
                    modelUndoController.redo()
                } label: {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                }
                .disabled(!modelUndoController.canRedo)
            }

            Section {
                Button(role: .destructive) {
                    showingRemoveAllConfirmation = true
                } label: {
                    dangerZoneLabel(
                        "Remove All Accounts",
                        systemImage: "trash",
                        isEnabled: hasSavedAccounts
                    )
                }
                .buttonStyle(.plain)
                .disabled(!hasSavedAccounts)
            } header: {
                Text("Danger Zone")
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog(
            "Remove all accounts?",
            isPresented: $showingRemoveAllConfirmation
        ) {
            Button("Remove All", role: .destructive) {
                removeAllAccounts()
            }
        } message: {
            Text("Remove every account from Apple Watch? You can add them again later from the Mac or iPhone.")
        }
        .alert(item: $presentedSettingsAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message)
            )
        }
    }

    private var hasSavedAccounts: Bool {
        !accounts.isEmpty
    }

    private func dangerZoneLabel(
        _ title: String,
        systemImage: String,
        isEnabled: Bool
    ) -> some View {
        Label(title, systemImage: systemImage)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(isEnabled ? .red : .secondary)
            .contentShape(Rectangle())
    }

    private func removeAllAccounts() {
        do {
            try StoredAccountMutations.removeAll(accounts, in: modelContext)
        } catch {
            presentedSettingsAlert = PresentedSettingsAlert(
                title: "Couldn't Remove Accounts",
                message: error.localizedDescription
            )
        }
    }
}
