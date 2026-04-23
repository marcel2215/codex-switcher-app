//
//  IOSRateLimitOverviewWidget.swift
//  Codex Switcher iOS Widgets
//
//  Created by Codex on 2026-04-13.
//

import SwiftUI
import WidgetKit

struct IOSRateLimitOverviewWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: CodexSharedSurfaceKinds.rateLimitOverviewWidget,
            intent: RateLimitOverviewConfigurationIntent.self,
            provider: RateLimitOverviewProvider()
        ) { entry in
            RateLimitOverviewWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Rate Limits")
        .description("Shows remaining 5h and 7d limits for selected Codex accounts.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

#Preview(as: .systemSmall) {
    IOSRateLimitOverviewWidget()
} timeline: {
    RateLimitOverviewEntry(date: .now, accounts: [WidgetRateLimitAccount.placeholder])
}

#Preview(as: .systemMedium) {
    IOSRateLimitOverviewWidget()
} timeline: {
    RateLimitOverviewEntry(
        date: .now,
        accounts: [
            WidgetRateLimitAccount.placeholder,
            WidgetRateLimitAccount.cachedPlaceholder,
        ]
    )
}
