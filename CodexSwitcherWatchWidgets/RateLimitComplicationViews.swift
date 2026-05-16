//
//  RateLimitComplicationViews.swift
//  Codex Switcher Watch Widgets
//
//  Created by Marcel Kwiatkowski on 2026-04-14.
//

import SwiftUI
import WidgetKit

struct WatchRateLimitCircularComplicationView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode

    let account: WidgetRateLimitAccount?
    let window: RateLimitWindow

    var body: some View {
        // Watch complications follow different layout rules than iPhone Lock
        // Screen accessories. Keep the circular variant to the native watchOS
        // circular gauge style so the face renderer can safely adapt it.
        Gauge(value: metric.fraction) {
            Text(window.shortLabel)
        } currentValueLabel: {
            Text(metric.complicationPercentText)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.65)
                .foregroundStyle(valueColor)
        }
        .gaugeStyle(.circular)
        .tint(gaugeTint)
        .widgetLabel {
            Text(window.shortLabel)
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
    }

    private var metric: WidgetRateLimitMetric {
        account?.metric(for: window) ?? .missingComplicationMetric
    }

    private var gaugeTint: Color {
        if widgetRenderingMode == .vibrant {
            return .white
        }

        return metric.tint(colorScheme: colorScheme, contrast: colorSchemeContrast)
    }

    private var valueColor: Color {
        widgetRenderingMode == .vibrant ? .white : .primary
    }

    private var accessibilityLabel: String {
        L10n.format(
            "%1$@ %2$@",
            account?.displayName ?? L10n.string("Missing Account", comment: "Widget fallback name for an account that no longer exists."),
            window.shortLabel,
            comment: "Accessibility label combining account name and rate-limit window short label."
        )
    }

    private var accessibilityValue: String {
        switch metric.status {
        case .exact:
            return L10n.format("%@ remaining", metric.percentText, comment: "Accessibility value for an exact rate-limit percentage.")
        case .cached:
            return L10n.format("%@ remaining, cached", metric.percentText, comment: "Accessibility value for a cached rate-limit percentage.")
        case .missing, .unavailable:
            return L10n.string("Unavailable", comment: "Accessibility value when a rate limit is unavailable.")
        }
    }
}

struct WatchRateLimitCornerComplicationView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode

    let account: WidgetRateLimitAccount?
    let window: RateLimitWindow

    var body: some View {
        // For accessoryCorner, the face expects a compact center view plus
        // extracted curved content from widgetLabel. Supplying the gauge in the
        // label matches Apple's documented complication pattern. Keep the
        // center content unadorned so the percentage reads as plain text rather
        // than looking like a separate circular badge inside the gauge.
        Text(metric.complicationPercentText)
            .font(.system(size: 19, weight: .bold, design: .rounded))
            .minimumScaleFactor(0.5)
            .foregroundStyle(valueColor)
            .widgetCurvesContent()
        .widgetLabel {
            Gauge(value: metric.fraction) {
                Text(window.shortLabel)
            }
            .tint(gaugeTint)
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
    }

    private var metric: WidgetRateLimitMetric {
        account?.metric(for: window) ?? .missingComplicationMetric
    }

    private var gaugeTint: Color {
        if widgetRenderingMode == .vibrant {
            return .white
        }

        return metric.tint(colorScheme: colorScheme, contrast: colorSchemeContrast)
    }

    private var valueColor: Color {
        widgetRenderingMode == .vibrant ? .white : .primary
    }

    private var accessibilityLabel: String {
        L10n.format(
            "%1$@ %2$@",
            account?.displayName ?? L10n.string("Missing Account", comment: "Widget fallback name for an account that no longer exists."),
            window.shortLabel,
            comment: "Accessibility label combining account name and rate-limit window short label."
        )
    }

    private var accessibilityValue: String {
        switch metric.status {
        case .exact:
            return L10n.format("%@ remaining", metric.percentText, comment: "Accessibility value for an exact rate-limit percentage.")
        case .cached:
            return L10n.format("%@ remaining, cached", metric.percentText, comment: "Accessibility value for a cached rate-limit percentage.")
        case .missing, .unavailable:
            return L10n.string("Unavailable", comment: "Accessibility value when a rate limit is unavailable.")
        }
    }
}

private extension WidgetRateLimitMetric {
    static let missingComplicationMetric = Self(
        remainingPercent: nil,
        resetsAt: nil,
        status: .missing
    )

    var complicationPercentText: String {
        guard let clampedPercent else {
            return "?"
        }

        return "\(clampedPercent)%"
    }
}
