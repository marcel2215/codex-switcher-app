//
//  WatchAccountNameEditorView.swift
//  Codex Switcher Watch App
//
//  Created by Codex on 2026-04-12.
//

import SwiftUI

struct WatchAccountNameEditorView: View {
    @Binding var draftName: String

    let placeholder: String
    let onSave: () -> Void

    private var prompt: String {
        let trimmedPlaceholder = placeholder.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedPlaceholder.isEmpty ? "Account Name" : trimmedPlaceholder
    }

    var body: some View {
        Form {
            TextField("Account Name", text: $draftName, prompt: Text(prompt))
                .submitLabel(.done)
                .onSubmit(onSave)
        }
        .navigationTitle("Name")
        .onDisappear(perform: onSave)
    }
}
