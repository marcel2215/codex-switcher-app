//
//  IOSAccountIconPickerView.swift
//  Codex Switcher iOS App
//
//  Created by Codex on 2026-04-11.
//

import SwiftData
import SwiftUI

struct IOSAccountIconPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let account: StoredAccount
    let controller: IOSAccountsController

    var body: some View {
        List(AccountIconOption.displayOrder) { icon in
            Button {
                controller.setIcon(icon, for: account, in: modelContext)
                dismiss()
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
