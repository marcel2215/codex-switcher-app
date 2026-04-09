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
            AccountRowView.makeMetadataDescription(
                lastLoginAt: lastLoginAt,
                sevenDayLimitUsedPercent: sevenDayLimitUsedPercent,
                fiveHourLimitUsedPercent: fiveHourLimitUsedPercent
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
        var value = AttributedString(AccountRowView.makeLastLoginValueDescription(from: lastLoginAt))
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
        guard let value else {
            return AttributedString("?")
        }

        let clamped = min(max(value, 0), 100)
        let components = usageColorComponents(forUsedPercent: clamped)
        var result = AttributedString("\(clamped)%")
        result.foregroundColor = Color(
            .sRGB,
            red: components.red,
            green: components.green,
            blue: components.blue,
            opacity: 1
        )
        return result
    }

    // The limits use a fixed visual scale:
    // 0% -> red, 50% -> yellow, 100% -> green.
    // Keep the interpolation deterministic so list rows and menu bar rows
    // always render the same meaning on every surface.
    static func usageColorComponents(forUsedPercent value: Int) -> (red: Double, green: Double, blue: Double) {
        let normalized = min(max(Double(value), 0), 100)

        if normalized <= 50 {
            let progress = normalized / 50
            return (red: 1, green: progress, blue: 0)
        }

        let progress = (normalized - 50) / 50
        return (red: 1 - progress, green: 1, blue: 0)
    }
}
