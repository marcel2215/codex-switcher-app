//
//  AccountMetadataText.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-09.
//

import SwiftUI

struct AccountMetadataText: View {
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
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Text(AccountDisplayFormatter.compactPercentDescription(remainingPercent))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.primary)
            }

            RateLimitLinearProgressBar(
                remainingPercent: remainingPercent,
                height: 2,
                trackOpacity: 0.25
            )
            .frame(maxWidth: .infinity)
        }
    }
}
