//
//  RateLimitResetText.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-18.
//

import SwiftUI

/// Renders the shared reset label policy used by the app and widgets:
/// use the system's live relative-date renderer for any future reset, then
/// swap to the static `now` label once the reset has passed.
struct RateLimitResetText: View {
    private static let refreshInterval: TimeInterval = 60

    let resetAt: Date?
    let fallbackText: String
    var displayMode: AccountDisplayFormatter.ResetTimeDisplayMode = .relative

    var body: some View {
        let now = Date.now

        switch displayMode {
        case .absolute:
            Text(
                AccountDisplayFormatter.resetTimeDescription(
                    until: resetAt,
                    displayMode: .absolute,
                    relativeTo: now
                )
            )
        case .relative:
            if let resetAt, resetAt.timeIntervalSince(now) > 0 {
                // Keep the label on a minute cadence so SwiftUI reevaluates the
                // `now` fallback as soon as the future reset has passed.
                TimelineView(.periodic(from: now, by: Self.refreshInterval)) { context in
                    relativeLabel(relativeTo: context.date)
                }
            } else {
                relativeLabel(relativeTo: now)
            }
        }
    }

    @ViewBuilder
    private func relativeLabel(relativeTo now: Date) -> some View {
        if let resetAt,
           AccountDisplayFormatter.shouldUseLiveWidgetCountdown(
               until: resetAt,
               relativeTo: now
           ) {
            Text(resetAt, style: .relative)
                .monospacedDigit()
        } else {
            Text(
                AccountDisplayFormatter.progressResetLabel(
                    until: resetAt,
                    fallbackTitle: fallbackText,
                    relativeTo: now
                )
            )
        }
    }
}
