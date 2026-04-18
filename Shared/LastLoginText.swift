//
//  LastLoginText.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-18.
//

import SwiftUI

/// Renders the visible last-login label using SwiftUI's relative-date API
/// while clamping future-skewed timestamps back to `now`.
struct LastLoginText: View {
    let lastLoginAt: Date?

    var body: some View {
        if let lastLoginAt {
            Text(min(lastLoginAt, .now), style: .relative)
                .monospacedDigit()
        } else {
            Text("never")
        }
    }
}
