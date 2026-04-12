//
//  IOSSettingsView.swift
//  Codex Switcher iOS App
//
//  Created by Codex on 2026-04-11.
//

import SwiftUI

struct IOSSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("About") {
                LabeledContent("Version") {
                    Text(AppAboutInfo.current.formattedVersion)
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
