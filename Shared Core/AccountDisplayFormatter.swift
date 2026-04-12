//
//  AccountDisplayFormatter.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-11.
//

import Foundation

enum AccountDisplayFormatter {
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
            "7d: \(compactPercentDescription(sevenDayRemainingPercent))",
            "5h: \(compactPercentDescription(fiveHourRemainingPercent))",
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
            "7 day remaining \(detailedPercentDescription(sevenDayRemainingPercent))",
            "5 hour remaining \(detailedPercentDescription(fiveHourRemainingPercent))",
        ].joined(separator: ", ")
    }

    static func compactUsageListDescription(
        sevenDayRemainingPercent: Int?,
        fiveHourRemainingPercent: Int?
    ) -> String {
        [
            "7d: \(compactPercentDescription(sevenDayRemainingPercent))",
            "5h: \(compactPercentDescription(fiveHourRemainingPercent))",
        ].joined(separator: " • ")
    }

    static func accessibilityUsageListDescription(
        sevenDayRemainingPercent: Int?,
        fiveHourRemainingPercent: Int?
    ) -> String {
        [
            "7 day remaining \(detailedPercentDescription(sevenDayRemainingPercent))",
            "5 hour remaining \(detailedPercentDescription(fiveHourRemainingPercent))",
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

    static func clampedPercentValue(_ value: Int?) -> Int? {
        guard let value else {
            return nil
        }

        return min(max(value, 0), 100)
    }

    // The list uses a deterministic remaining-capacity gradient:
    // 0% -> red, 50% -> yellow, 100% -> green.
    static func usageColorComponents(forRemainingPercent value: Int) -> (red: Double, green: Double, blue: Double) {
        let normalized = min(max(Double(value), 0), 100)

        if normalized <= 50 {
            let progress = normalized / 50
            return (red: 1, green: progress, blue: 0)
        }

        let progress = (normalized - 50) / 50
        return (red: 1 - progress, green: 1, blue: 0)
    }
}
