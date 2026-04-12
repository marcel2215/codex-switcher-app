//
//  WatchSettingsView.swift
//  Codex Switcher Watch App
//
//  Created by Codex on 2026-04-12.
//

import SwiftUI

struct WatchSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("About") {
                LabeledContent("Version") {
                    Text(AppAboutInfo.current.version)
                }

                LabeledContent("Build") {
                    Text(AppAboutInfo.current.build)
                }
            }

            Section("Links") {
                Link(destination: AppSupportLink.contactURL) {
                    Label("Contact Us", systemImage: "envelope")
                }

                Link(destination: AppSupportLink.privacyPolicyURL) {
                    Label("Privacy Policy", systemImage: "hand.raised")
                }

                Link(destination: AppSupportLink.sourceCodeURL) {
                    Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }
}
