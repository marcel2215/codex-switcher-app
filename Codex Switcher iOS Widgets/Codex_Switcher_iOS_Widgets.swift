//
//  Codex_Switcher_iOS_Widgets.swift
//  Codex Switcher iOS Widgets
//
//  Created by Codex on 2026-04-12.
//

import SwiftUI
import WidgetKit

struct RateLimitAccessoryWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: CodexSharedSurfaceKinds.rateLimitAccessoryWidget,
            intent: RateLimitAccessoryConfigurationIntent.self,
            provider: RateLimitAccessoryProvider()
        ) { entry in
            RateLimitAccessoryWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Rate Limit")
        .description("Shows one account's remaining 5h or 7d limit.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

private struct RateLimitAccessoryWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family

    let entry: RateLimitAccessoryEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            RateLimitCircularAccessoryView(
                account: entry.account,
                window: entry.window
            )
        default:
            RateLimitRectangularAccessoryView(
                account: entry.account,
                window: entry.window
            )
        }
    }
}
