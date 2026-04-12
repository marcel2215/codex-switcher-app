//
//  WatchAccountIconPickerView.swift
//  Codex Switcher Watch App
//
//  Created by Codex on 2026-04-12.
//

import SwiftData
import SwiftUI

struct WatchAccountIconPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let account: StoredAccount
    let onError: (PresentedError) -> Void

    var body: some View {
        List(AccountIconOption.displayOrder) { icon in
            Button {
                do {
                    try StoredAccountMutations.setIcon(icon, for: account, in: modelContext)
                    dismiss()
                } catch {
                    onError(
                        PresentedError(
                            title: "Couldn't Change Icon",
                            message: error.localizedDescription
                        )
                    )
                }
            } label: {
                HStack {
                    Label(icon.title, systemImage: icon.systemName)
                    Spacer()

                    if AccountIconOption.resolve(from: account.iconSystemName) == icon {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                    }
                }
            }
            .foregroundStyle(.primary)
        }
        .navigationTitle("Choose Icon")
    }
}
