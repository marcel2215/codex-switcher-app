//
//  WatchOpenAppComplicationWidget.swift
//  Codex Switcher Watch Widgets
//
//  Created by Codex on 2026-04-14.
//

import SwiftUI
import WidgetKit

private let watchOpenAppComplicationSymbolName = "arrow.left.arrow.right"

struct WatchOpenAppComplicationEntry: TimelineEntry {
    let date: Date
}

struct WatchOpenAppComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchOpenAppComplicationEntry {
        WatchOpenAppComplicationEntry(date: .now)
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (WatchOpenAppComplicationEntry) -> Void
    ) {
        completion(WatchOpenAppComplicationEntry(date: .now))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<WatchOpenAppComplicationEntry>) -> Void
    ) {
        completion(
            Timeline(
                entries: [WatchOpenAppComplicationEntry(date: .now)],
                policy: .never
            )
        )
    }
}

struct WatchOpenAppComplicationWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: CodexSharedSurfaceKinds.openAppWatchComplication,
            provider: WatchOpenAppComplicationProvider()
        ) { entry in
            WatchOpenAppComplicationEntryView(entry: entry)
        }
        .configurationDisplayName("Open Codex Switcher")
        .description("Shows a quick launcher that opens Codex Switcher on Apple Watch.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner])
    }
}

private struct WatchOpenAppComplicationEntryView: View {
    @Environment(\.widgetFamily) private var family

    let entry: WatchOpenAppComplicationEntry

    var body: some View {
        complicationContent
            // Complication taps already launch the containing app by default, so
            // this widget only needs to render the launcher glyph.
            .containerBackground(for: .widget) {
                Color.clear
            }
            .accessibilityLabel("Open Codex Switcher")
    }

    @ViewBuilder
    private var complicationContent: some View {
        switch family {
        case .accessoryCircular:
            WatchOpenAppCircularComplicationView()
        case .accessoryCorner:
            WatchOpenAppCornerComplicationView()
        default:
            EmptyView()
        }
    }
}

private struct WatchOpenAppCircularComplicationView: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(.tertiary, lineWidth: 2.5)

            Image(systemName: watchOpenAppComplicationSymbolName)
                .font(.system(size: 18, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .widgetAccentable()
        }
        .padding(4)
    }
}

private struct WatchOpenAppCornerComplicationView: View {
    var body: some View {
        ZStack {
            AccessoryWidgetBackground()

            Image(systemName: watchOpenAppComplicationSymbolName)
                .font(.system(size: 14, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .widgetAccentable()
        }
        .padding(4)
    }
}

#Preview(as: .accessoryCircular) {
    WatchOpenAppComplicationWidget()
} timeline: {
    WatchOpenAppComplicationEntry(date: .now)
}

#Preview(as: .accessoryCorner) {
    WatchOpenAppComplicationWidget()
} timeline: {
    WatchOpenAppComplicationEntry(date: .now)
}
