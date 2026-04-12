//
//  IOSAccountRow.swift
//  Codex Switcher iOS App
//
//  Created by Codex on 2026-04-11.
//

import SwiftUI

struct IOSAccountRow: View {
    let account: StoredAccount

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: AccountIconOption.resolve(from: account.iconSystemName).systemName)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(AccountsPresentationLogic.displayName(for: account))
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 12) {
                    IOSRateLimitProgressBar(
                        title: "5h",
                        remainingPercent: account.fiveHourLimitUsedPercent
                    )

                    IOSRateLimitProgressBar(
                        title: "7d",
                        remainingPercent: account.sevenDayLimitUsedPercent
                    )
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(AccountsPresentationLogic.displayName(for: account)), \(AccountDisplayFormatter.accessibilityUsageListDescription(sevenDayRemainingPercent: account.sevenDayLimitUsedPercent, fiveHourRemainingPercent: account.fiveHourLimitUsedPercent))"
        )
    }
}

private struct IOSRateLimitProgressBar: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let title: String
    let remainingPercent: Int?

    private var normalizedProgress: Double? {
        guard let clampedPercent = AccountDisplayFormatter.clampedPercentValue(remainingPercent) else {
            return nil
        }

        return Double(clampedPercent) / 100
    }

    private var progressTint: Color {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
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
                        .tint(progressTint)
                } else {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.tertiary.opacity(0.25))
                        .frame(height: 4)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private static func colorRamp(
        for colorScheme: ColorScheme,
        contrast: ColorSchemeContrast
    ) -> (
        low: (red: Double, green: Double, blue: Double),
        mid: (red: Double, green: Double, blue: Double),
        high: (red: Double, green: Double, blue: Double)
    ) {
        // The row uses slightly deeper tones in light mode and brighter tones
        // in dark mode so the narrow progress fill stays readable against the
        // system list background in both appearances.
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
