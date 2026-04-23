//
//  StorageUnavailableView.swift
//  Codex Switcher Watch App
//
//  Created by Marcel Kwiatkowski on 2026-04-12.
//

import SwiftUI

struct WatchStorageUnavailableView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            ContentUnavailableView(
                "Storage Unavailable",
                systemImage: "externaldrive.badge.xmark",
                description: Text("Codex Switcher couldn't open its iCloud-backed account database. \(message)")
            )

            Button("Retry", action: onRetry)
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
