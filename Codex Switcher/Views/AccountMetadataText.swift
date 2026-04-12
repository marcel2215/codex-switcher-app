//
//  AccountMetadataText.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-09.
//

import SwiftUI

struct AccountMetadataText: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let lastLoginAt: Date?
    let sevenDayLimitUsedPercent: Int?
    let fiveHourLimitUsedPercent: Int?
    let sevenDayResetsAt: Date?
    let fiveHourResetsAt: Date?
    let font: Font

    init(
        lastLoginAt: Date?,
        sevenDayLimitUsedPercent: Int?,
        fiveHourLimitUsedPercent: Int?,
        sevenDayResetsAt: Date? = nil,
        fiveHourResetsAt: Date? = nil,
        font: Font = .subheadline
    ) {
        self.lastLoginAt = lastLoginAt
        self.sevenDayLimitUsedPercent = sevenDayLimitUsedPercent
        self.fiveHourLimitUsedPercent = fiveHourLimitUsedPercent
        self.sevenDayResetsAt = sevenDayResetsAt
        self.fiveHourResetsAt = fiveHourResetsAt
        self.font = font
    }

    var body: some View {
        // Keep the existing initializer surface so the macOS list and menu bar
        // call sites remain stable while the row UI now mirrors iOS.
        HStack(spacing: 6) {
            progressBar(
                title: progressLabel(fallbackTitle: "5h", resetAt: fiveHourResetsAt),
                remainingPercent: fiveHourLimitUsedPercent
            )
            progressBar(
                title: progressLabel(fallbackTitle: "7d", resetAt: sevenDayResetsAt),
                remainingPercent: sevenDayLimitUsedPercent
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            AccountDisplayFormatter.accessibilityUsageListDescription(
                sevenDayRemainingPercent: sevenDayLimitUsedPercent,
                fiveHourRemainingPercent: fiveHourLimitUsedPercent
            )
        )
    }

    static func makeAttributedDescription(
        lastLoginAt: Date?,
        sevenDayLimitUsedPercent: Int?,
        fiveHourLimitUsedPercent: Int?,
        sevenDayResetsAt: Date? = nil,
        fiveHourResetsAt: Date? = nil,
        relativeTo now: Date = .now
    ) -> AttributedString {
        var result = lastLoginFragment(lastLoginAt)

        result.append(AttributedString(" • "))
        result.append(
            limitFragment(
                label: progressLabel(fallbackTitle: "7d", resetAt: sevenDayResetsAt, relativeTo: now),
                value: sevenDayLimitUsedPercent
            )
        )
        result.append(AttributedString(" • "))
        result.append(
            limitFragment(
                label: progressLabel(fallbackTitle: "5h", resetAt: fiveHourResetsAt, relativeTo: now),
                value: fiveHourLimitUsedPercent
            )
        )

        return result
    }

    private static func lastLoginFragment(_ lastLoginAt: Date?) -> AttributedString {
        var result = AttributedString("Last login: ")
        var value = AttributedString(AccountDisplayFormatter.lastLoginValueDescription(from: lastLoginAt))
        value.foregroundColor = .primary
        result.append(value)
        return result
    }

    private static func limitFragment(label: String, value: Int?) -> AttributedString {
        var result = AttributedString("\(label): ")
        result.append(percentFragment(value))
        return result
    }

    private static func percentFragment(_ value: Int?) -> AttributedString {
        guard let clampedValue = AccountDisplayFormatter.clampedPercentValue(value) else {
            return AttributedString("?")
        }

        return AttributedString("\(clampedValue)%")
    }

    private func progressLabel(fallbackTitle: String, resetAt: Date?) -> String {
        Self.progressLabel(fallbackTitle: fallbackTitle, resetAt: resetAt, relativeTo: .now)
    }

    private static func progressLabel(
        fallbackTitle: String,
        resetAt: Date?,
        relativeTo now: Date
    ) -> String {
        AccountDisplayFormatter.progressResetLabel(
            until: resetAt,
            fallbackTitle: fallbackTitle,
            relativeTo: now
        )
    }

    @ViewBuilder
    private func progressBar(title: String, remainingPercent: Int?) -> some View {
        let normalizedProgress = Self.normalizedProgress(for: remainingPercent)

        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Text(AccountDisplayFormatter.compactPercentDescription(remainingPercent))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Group {
                if let normalizedProgress {
                    ProgressView(value: normalizedProgress, total: 1)
                        .progressViewStyle(.linear)
                        .tint(progressTint(for: remainingPercent))
                        .scaleEffect(y: 0.55, anchor: .center)
                } else {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.tertiary.opacity(0.25))
                        .frame(height: 2)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func progressTint(for remainingPercent: Int?) -> Color {
        let clampedPercent = AccountDisplayFormatter.clampedPercentValue(remainingPercent) ?? 0
        let ramp = Self.colorRamp(for: colorScheme, contrast: colorSchemeContrast)
        let components = Self.interpolatedColorComponents(
            forRemainingPercent: clampedPercent,
            low: ramp.low,
            mid: ramp.mid,
            high: ramp.high
        )

        return Color(.sRGB, red: components.red, green: components.green, blue: components.blue)
    }

    private static func normalizedProgress(for remainingPercent: Int?) -> Double? {
        guard let clampedPercent = AccountDisplayFormatter.clampedPercentValue(remainingPercent) else {
            return nil
        }

        return Double(clampedPercent) / 100
    }

    private static func colorRamp(
        for colorScheme: ColorScheme,
        contrast: ColorSchemeContrast
    ) -> (
        low: (red: Double, green: Double, blue: Double),
        mid: (red: Double, green: Double, blue: Double),
        high: (red: Double, green: Double, blue: Double)
    ) {
        // The macOS list uses the same adaptive ramp as iOS so the compact bar
        // remains legible against both light and dark sidebar backgrounds.
        switch (colorScheme, contrast) {
        case (.light, .increased):
            return (
                low: (0.68, 0.12, 0.10),
                mid: (0.78, 0.34, 0.00),
                high: (0.08, 0.46, 0.17)
            )
        case (.dark, .increased):
            return (
                low: (1.00, 0.48, 0.45),
                mid: (1.00, 0.73, 0.28),
                high: (0.46, 0.95, 0.54)
            )
        case (.dark, _):
            return (
                low: (1.00, 0.39, 0.36),
                mid: (1.00, 0.62, 0.18),
                high: (0.35, 0.84, 0.43)
            )
        case (.light, _):
            return (
                low: (0.78, 0.19, 0.17),
                mid: (0.87, 0.46, 0.07),
                high: (0.12, 0.56, 0.23)
            )
        @unknown default:
            return (
                low: (0.78, 0.19, 0.17),
                mid: (0.87, 0.46, 0.07),
                high: (0.12, 0.56, 0.23)
            )
        }
    }

    private static func interpolatedColorComponents(
        forRemainingPercent percent: Int,
        low: (red: Double, green: Double, blue: Double),
        mid: (red: Double, green: Double, blue: Double),
        high: (red: Double, green: Double, blue: Double)
    ) -> (red: Double, green: Double, blue: Double) {
        let normalized = min(max(Double(percent), 0), 100)

        if normalized <= 50 {
            let progress = normalized / 50
            return (
                red: low.red + ((mid.red - low.red) * progress),
                green: low.green + ((mid.green - low.green) * progress),
                blue: low.blue + ((mid.blue - low.blue) * progress)
            )
        }

        let progress = (normalized - 50) / 50
        return (
            red: mid.red + ((high.red - mid.red) * progress),
            green: mid.green + ((high.green - mid.green) * progress),
            blue: mid.blue + ((high.blue - mid.blue) * progress)
        )
    }
}
