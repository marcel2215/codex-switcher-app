//
//  IOSAccountNameEditorView.swift
//  Codex Switcher iOS App
//
//  Created by Codex on 2026-04-11.
//

import SwiftUI

struct IOSAccountNameEditorView: View {
    @Binding var draftName: String

    let placeholder: String
    let onSave: () -> Void

    var body: some View {
        Form {
            Section {
                TextField(
                    "",
                    text: $draftName,
                    prompt: Text(placeholder)
                )
                .labelsHidden()
                .submitLabel(.done)
                .onSubmit(onSave)
            }
        }
        .navigationTitle("Name")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear(perform: onSave)
    }
}
