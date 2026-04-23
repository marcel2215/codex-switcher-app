//
//  StorageUnavailableView.swift
//  Codex Switcher
//
//  Created by Marcel Kwiatkowski on 2026-04-11.
//

import SwiftUI

struct StorageUnavailableView: View {
    let message: String

    var body: some View {
        ContentUnavailableView(
            "Storage Unavailable",
            systemImage: "externaldrive.badge.xmark",
            description: Text("Codex Switcher couldn't open its iCloud-backed account database. \(message)")
        )
        .padding()
    }
}
