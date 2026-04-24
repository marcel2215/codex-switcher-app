//
//  AccountMetadataText.swift
//  Codex Switcher Mac App
//
//  Created by Marcel Kwiatkowski on 2026-04-09.
//

import SwiftUI

struct AccountMetadataText: View {
    let lastLoginAt: Date?
    let sevenDayLimitUsedPercent: Int?
    let fiveHourLimitUsedPercent: Int?
    let sevenDayResetsAt: Date?
    let fiveHourResetsAt: Date?
    let isUnavailable: Bool
    let font: Font

    init(
        lastLoginAt: Date?,
        sevenDayLimitUsedPercent: Int?,
        fiveHourLimitUsedPercent: Int?,
        sevenDayResetsAt: Date? = nil,
        fiveHourResetsAt: Date? = nil,
        isUnavailable: Bool = false,
        font: Font = .subheadline
    ) {
        self.lastLoginAt = lastLoginAt
        self.sevenDayLimitUsedPercent = sevenDayLimitUsedPercent
        self.fiveHourLimitUsedPercent = fiveHourLimitUsedPercent
        self.sevenDayResetsAt = sevenDayResetsAt
        self.fiveHourResetsAt = fiveHourResetsAt
        self.isUnavailable = isUnavailable
        self.font = font
    }

    var body: some View {
        // Keep the existing initializer surface so the macOS list and menu bar
        // call sites remain stable while the row UI now mirrors iOS.
        HStack(spacing: 6) {
            progressBar(
                fallbackTitle: "5h",
                resetAt: fiveHourResetsAt,
                remainingPercent: fiveHourLimitUsedPercent
            )
            progressBar(
                fallbackTitle: "7d",
                resetAt: sevenDayResetsAt,
                remainingPercent: sevenDayLimitUsedPercent
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            AccountDisplayFormatter.accessibilityUsageListDescription(
                sevenDayRemainingPercent: sevenDayDisplayLimitPercent,
                fiveHourRemainingPercent: fiveHourDisplayLimitPercent
            )
        )
    }

    private var sevenDayDisplayLimitPercent: Int? {
        isUnavailable ? nil : sevenDayLimitUsedPercent
    }

    private var fiveHourDisplayLimitPercent: Int? {
        isUnavailable ? nil : fiveHourLimitUsedPercent
    }

    static func makeAttributedDescription(
        lastLoginAt: Date?,
        sevenDayLimitUsedPercent: Int?,
        fiveHourLimitUsedPercent: Int?,
        sevenDayResetsAt: Date? = nil,
        fiveHourResetsAt: Date? = nil,
        isUnavailable: Bool = false,
        relativeTo now: Date = .now
    ) -> AttributedString {
        var result = lastLoginFragment(lastLoginAt)
        let displayedSevenDayLimitUsedPercent = isUnavailable ? nil : sevenDayLimitUsedPercent
        let displayedFiveHourLimitUsedPercent = isUnavailable ? nil : fiveHourLimitUsedPercent

        result.append(AttributedString(" • "))
        result.append(
            limitFragment(
                label: progressLabel(fallbackTitle: "7d", resetAt: sevenDayResetsAt, relativeTo: now),
                value: displayedSevenDayLimitUsedPercent
            )
        )
        result.append(AttributedString(" • "))
        result.append(
            limitFragment(
                label: progressLabel(fallbackTitle: "5h", resetAt: fiveHourResetsAt, relativeTo: now),
                value: displayedFiveHourLimitUsedPercent
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
    private func progressBar(
        fallbackTitle: String,
        resetAt: Date?,
        remainingPercent: Int?
    ) -> some View {
        let displayedRemainingPercent = isUnavailable ? nil : remainingPercent

        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                RateLimitResetText(
                    resetAt: resetAt,
                    fallbackText: fallbackTitle
                )
                    .monospacedDigit()
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Text(AccountDisplayFormatter.compactPercentDescription(
                    remainingPercent,
                    isUnavailable: isUnavailable
                ))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.primary)
            }

            RateLimitLinearProgressBar(
                remainingPercent: displayedRemainingPercent,
                height: 2,
                trackOpacity: 0.25
            )
            .frame(maxWidth: .infinity)
        }
    }
}
