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
                    Text(AppAboutInfo.current.formattedVersion)
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
