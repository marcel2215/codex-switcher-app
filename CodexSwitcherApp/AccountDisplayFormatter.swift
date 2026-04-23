//
//  AccountDisplayFormatter.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-11.
//

import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

enum AccountDisplayFormatter {
    enum ResetTimeDisplayMode: Sendable {
        case relative
        case absolute
    }

    static func lastLoginValueDescription(from lastLoginAt: Date?, relativeTo now: Date = .now) -> String {
        guard let lastLoginAt else {
            return "never"
        }

        // Manual clock changes and skew should not produce future-facing copy.
        let elapsedSeconds = max(now.timeIntervalSince(lastLoginAt), 0)
        let hourInSeconds: TimeInterval = 60 * 60
        let dayInSeconds: TimeInterval = 24 * hourInSeconds

        if elapsedSeconds < hourInSeconds {
            return "this hour"
        }

        if elapsedSeconds < dayInSeconds {
            return "\(Int(elapsedSeconds / hourInSeconds))h ago"
        }

        return "\(max(Int(elapsedSeconds / dayInSeconds), 1))d ago"
    }

    static func lastLoginListDescription(from lastLoginAt: Date?, relativeTo now: Date = .now) -> String {
        "Last login: \(lastLoginValueDescription(from: lastLoginAt, relativeTo: now))"
    }

    static func listMetadataDescription(
        lastLoginAt: Date?,
        sevenDayRemainingPercent: Int?,
        fiveHourRemainingPercent: Int?,
        relativeTo now: Date = .now
    ) -> String {
        [
            lastLoginListDescription(from: lastLoginAt, relativeTo: now),
            "5h: \(compactPercentDescription(fiveHourRemainingPercent))",
            "7d: \(compactPercentDescription(sevenDayRemainingPercent))",
        ].joined(separator: " • ")
    }

    static func accessibilityMetadataDescription(
        lastLoginAt: Date?,
        sevenDayRemainingPercent: Int?,
        fiveHourRemainingPercent: Int?,
        relativeTo now: Date = .now
    ) -> String {
        [
            "Last login \(lastLoginValueDescription(from: lastLoginAt, relativeTo: now))",
            "5 hour remaining \(detailedPercentDescription(fiveHourRemainingPercent))",
            "7 day remaining \(detailedPercentDescription(sevenDayRemainingPercent))",
        ].joined(separator: ", ")
    }

    static func compactUsageListDescription(
        sevenDayRemainingPercent: Int?,
        fiveHourRemainingPercent: Int?
    ) -> String {
        [
            "5h: \(compactPercentDescription(fiveHourRemainingPercent))",
            "7d: \(compactPercentDescription(sevenDayRemainingPercent))",
        ].joined(separator: " • ")
    }

    static func accessibilityUsageListDescription(
        sevenDayRemainingPercent: Int?,
        fiveHourRemainingPercent: Int?
    ) -> String {
        [
            "5 hour remaining \(detailedPercentDescription(fiveHourRemainingPercent))",
            "7 day remaining \(detailedPercentDescription(sevenDayRemainingPercent))",
        ].joined(separator: ", ")
    }

    static func compactPercentDescription(_ value: Int?) -> String {
        guard let clampedPercent = clampedPercentValue(value) else {
            return "?"
        }

        return "\(clampedPercent)%"
    }

    static func detailedPercentDescription(_ value: Int?) -> String {
        guard let clampedPercent = clampedPercentValue(value) else {
            return "Unavailable"
        }

        return "\(clampedPercent)%"
    }

    /// Produces a compact reset countdown for detail views.
    /// The output deliberately caps itself at two units so the value remains
    /// readable inside a `LabeledContent` trailing column.
    static func resetCountdownDescription(until resetAt: Date?, relativeTo now: Date = .now) -> String {
        guard let resetAt else {
            return "Unavailable"
        }

        let remainingSeconds = resetAt.timeIntervalSince(now)
        guard remainingSeconds > 0 else {
            return "now"
        }

        // Round up to the next minute so a future reset never appears as "now"
        // or "0m" before the boundary is actually reached.
        let totalMinutes = Int(ceil(remainingSeconds / 60))

        if totalMinutes < 60 {
            return "\(max(totalMinutes, 1))m"
        }

        let totalHours = totalMinutes / 60
        let remainingMinutes = totalMinutes % 60

        if totalHours < 24 {
            if remainingMinutes == 0 {
                return "\(totalHours)h"
            }

            return "\(totalHours)h \(remainingMinutes)m"
        }

        let days = totalHours / 24
        let remainingHours = totalHours % 24

        if remainingHours == 0 {
            return "\(days)d"
        }

        return "\(days)d \(remainingHours)h"
    }

    static func resetTimeDescription(
        until resetAt: Date?,
        displayMode: ResetTimeDisplayMode,
        relativeTo now: Date = .now
    ) -> String {
        switch displayMode {
        case .relative:
            return resetCountdownDescription(until: resetAt, relativeTo: now)
        case .absolute:
            guard let resetAt else {
                return "Unavailable"
            }

            return resetAt.formatted(date: .abbreviated, time: .shortened)
        }
    }

    static func progressResetLabel(
        until resetAt: Date?,
        fallbackTitle: String,
        relativeTo now: Date = .now
    ) -> String {
        guard resetAt != nil else {
            return fallbackTitle
        }

        return resetCountdownDescription(until: resetAt, relativeTo: now)
    }

    /// App and widget surfaces use the live system relative-date renderer for
    /// any future reset date, then swap to the static `now` label once the
    /// reset has passed.
    static func shouldUseLiveWidgetCountdown(
        until resetAt: Date?,
        relativeTo now: Date = .now
    ) -> Bool {
        guard let resetAt else {
            return false
        }

        return resetAt.timeIntervalSince(now) > 0
    }

    /// Returns the next moment a live relative reset label needs a view reload.
    /// The system keeps the relative text itself up to date, so surfaces only
    /// need to refresh when the future reset becomes the static `now` label.
    static func nextResetLabelRefreshDate(
        until resetAt: Date?,
        relativeTo now: Date = .now
    ) -> Date? {
        guard let resetAt else {
            return nil
        }

        let remainingSeconds = resetAt.timeIntervalSince(now)
        guard remainingSeconds > 0 else {
            return nil
        }

        return resetAt
    }

    static func clampedPercentValue(_ value: Int?) -> Int? {
        guard let value else {
            return nil
        }

        return min(max(value, 0), 100)
    }

    // The compact usage bars use a deterministic remaining-capacity gradient:
    // 0% -> red, 50% -> orange, 100% -> green.
    // This keeps low remaining capacity highly visible without relying on
    // yellow, which is harder to read against light list backgrounds.
    static func usageColorComponents(forRemainingPercent value: Int) -> (red: Double, green: Double, blue: Double) {
        let normalized = min(max(Double(value), 0), 100)

        if normalized <= 50 {
            let progress = normalized / 50
            return (red: 1, green: 0.38 * progress, blue: 0)
        }

        let progress = (normalized - 50) / 50
        return (red: 1 - progress, green: 0.38 + (0.62 * progress), blue: 0)
    }

#if canImport(SwiftUI)
    static func adaptiveUsageColorComponents(
        forRemainingPercent value: Int,
        colorScheme: ColorScheme,
        contrast: ColorSchemeContrast
    ) -> (red: Double, green: Double, blue: Double) {
        let ramp = usageColorRamp(for: colorScheme, contrast: contrast)
        let normalized = min(max(Double(value), 0), 100)

        if normalized <= 50 {
            let progress = normalized / 50
            return (
                red: ramp.low.red + ((ramp.mid.red - ramp.low.red) * progress),
                green: ramp.low.green + ((ramp.mid.green - ramp.low.green) * progress),
                blue: ramp.low.blue + ((ramp.mid.blue - ramp.low.blue) * progress)
            )
        }

        let progress = (normalized - 50) / 50
        return (
            red: ramp.mid.red + ((ramp.high.red - ramp.mid.red) * progress),
            green: ramp.mid.green + ((ramp.high.green - ramp.mid.green) * progress),
            blue: ramp.mid.blue + ((ramp.high.blue - ramp.mid.blue) * progress)
        )
    }

    private static func usageColorRamp(
        for colorScheme: ColorScheme,
        contrast: ColorSchemeContrast
    ) -> (
        low: (red: Double, green: Double, blue: Double),
        mid: (red: Double, green: Double, blue: Double),
        high: (red: Double, green: Double, blue: Double)
    ) {
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
#endif
}
