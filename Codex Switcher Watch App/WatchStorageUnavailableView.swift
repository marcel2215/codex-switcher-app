//
//  WatchStorageUnavailableView.swift
//  Codex Switcher Watch App
//
//  Created by Codex on 2026-04-12.
//

import SwiftUI

struct WatchStorageUnavailableView: View {
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
