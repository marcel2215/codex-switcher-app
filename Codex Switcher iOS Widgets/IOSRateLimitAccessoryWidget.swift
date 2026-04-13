//
//  IOSRateLimitAccessoryWidget.swift
//  Codex Switcher iOS Widgets
//
//  Created by Codex on 2026-04-13.
//

import SwiftUI
import WidgetKit

struct IOSRateLimitAccessoryWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: CodexSharedSurfaceKinds.rateLimitAccessoryWidget,
            intent: RateLimitAccessoryConfigurationIntent.self,
            provider: RateLimitAccessoryProvider()
        ) { entry in
            IOSRateLimitAccessoryWidgetView(entry: entry)
        }
        .configurationDisplayName("Rate Limit")
        .description("Shows one account's remaining 5h or 7d rate limit on the Lock Screen.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

private struct IOSRateLimitAccessoryWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: RateLimitAccessoryEntry

    @ViewBuilder
    var body: some View {
        switch family {
        case .accessoryCircular:
            RateLimitCircularAccessoryView(
                account: entry.account,
                window: entry.window
            )
        case .accessoryRectangular:
            RateLimitRectangularAccessoryView(
                account: entry.account,
                window: entry.window
            )
        default:
            EmptyView()
        }
    }
}

#Preview(as: .accessoryCircular) {
    IOSRateLimitAccessoryWidget()
} timeline: {
    RateLimitAccessoryEntry(
        date: .now,
        account: WidgetRateLimitAccount.placeholder,
        window: .fiveHour
    )
}

#Preview(as: .accessoryRectangular) {
    IOSRateLimitAccessoryWidget()
} timeline: {
    RateLimitAccessoryEntry(
        date: .now,
        account: WidgetRateLimitAccount.placeholder,
        window: .sevenDay
    )
}
