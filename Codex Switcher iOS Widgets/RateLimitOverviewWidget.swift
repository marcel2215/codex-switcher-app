//
//  RateLimitOverviewWidget.swift
//  Codex Switcher iOS Widgets
//
//  Created by Codex on 2026-04-12.
//

import SwiftUI
import WidgetKit

struct RateLimitOverviewWidget: Widget {
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
