//
//  RateLimitComplication.swift
//  Codex Switcher Watch Widgets
//
//  Created by Codex on 2026-04-14.
//

import SwiftUI
import WidgetKit

struct RateLimitComplication: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: CodexSharedSurfaceKinds.rateLimitWatchComplication,
            intent: RateLimitAccessoryConfigurationIntent.self,
            provider: RateLimitAccessoryProvider()
        ) { entry in
            WatchRateLimitComplicationEntryView(entry: entry)
        }
        .configurationDisplayName("Rate Limit")
        .description("Shows one account's remaining 5h or 7d rate limit as a watch complication.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner])
    }
}

private struct WatchRateLimitComplicationEntryView: View {
    @Environment(\.widgetFamily) private var family

    let entry: RateLimitAccessoryEntry

    var body: some View {
        complicationContent
            // watchOS still expects accessory complications to declare a root
            // widget background, even when the face ultimately removes it.
            .containerBackground(for: .widget) {
                Color.clear
            }
    }

    @ViewBuilder
    private var complicationContent: some View {
        switch family {
        case .accessoryCircular:
            WatchRateLimitCircularComplicationView(
                account: entry.account,
                window: entry.window
            )
        case .accessoryCorner:
            WatchRateLimitCornerComplicationView(
                account: entry.account,
                window: entry.window
            )
        default:
            EmptyView()
        }
    }
}

#Preview(as: .accessoryCircular) {
    RateLimitComplication()
} timeline: {
    RateLimitAccessoryEntry(
        date: .now,
        account: WidgetRateLimitAccount.placeholder,
        window: .fiveHour
    )
}

#Preview(as: .accessoryCorner) {
    RateLimitComplication()
} timeline: {
    RateLimitAccessoryEntry(
        date: .now,
        account: WidgetRateLimitAccount.cachedPlaceholder,
        window: .sevenDay
    )
}
