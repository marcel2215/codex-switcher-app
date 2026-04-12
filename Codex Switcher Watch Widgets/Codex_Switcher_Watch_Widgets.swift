//
//  Codex_Switcher_Watch_Widgets.swift
//  Codex Switcher Watch Widgets
//
//  Created by Codex on 2026-04-12.
//

import SwiftUI
import WidgetKit

struct RateLimitComplicationWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: CodexSharedSurfaceKinds.rateLimitWatchComplication,
            intent: RateLimitAccessoryConfigurationIntent.self,
            provider: RateLimitAccessoryProvider()
        ) { entry in
            RateLimitCircularAccessoryView(
                account: entry.account,
                window: entry.window
            )
        }
        .configurationDisplayName("Rate Limit")
        .description("Shows a Codex account's 5h or 7d limit.")
        .supportedFamilies([.accessoryCircular])
    }
}
