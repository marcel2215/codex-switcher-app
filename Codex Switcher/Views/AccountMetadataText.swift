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
    let font: Font

    init(
        lastLoginAt: Date?,
        sevenDayLimitUsedPercent: Int?,
        fiveHourLimitUsedPercent: Int?,
        font: Font = .subheadline
    ) {
        self.lastLoginAt = lastLoginAt
        self.sevenDayLimitUsedPercent = sevenDayLimitUsedPercent
        self.fiveHourLimitUsedPercent = fiveHourLimitUsedPercent
        self.font = font
    }

    var body: some View {
        Text(Self.makeAttributedDescription(
            lastLoginAt: lastLoginAt,
            sevenDayLimitUsedPercent: sevenDayLimitUsedPercent,
            fiveHourLimitUsedPercent: fiveHourLimitUsedPercent
        ))
        .font(font)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.tail)
        .accessibilityLabel(
            AccountDisplayFormatter.accessibilityMetadataDescription(
                lastLoginAt: lastLoginAt,
                sevenDayRemainingPercent: sevenDayLimitUsedPercent,
                fiveHourRemainingPercent: fiveHourLimitUsedPercent
            )
        )
    }

    static func makeAttributedDescription(
        lastLoginAt: Date?,
        sevenDayLimitUsedPercent: Int?,
        fiveHourLimitUsedPercent: Int?
    ) -> AttributedString {
        var result = lastLoginFragment(lastLoginAt)

        result.append(AttributedString(" • "))
        result.append(limitFragment(label: "7d", value: sevenDayLimitUsedPercent))
        result.append(AttributedString(" • "))
        result.append(limitFragment(label: "5h", value: fiveHourLimitUsedPercent))

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
}
