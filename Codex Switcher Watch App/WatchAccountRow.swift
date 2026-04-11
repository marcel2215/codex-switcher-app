//
//  WatchAccountRow.swift
//  Codex Switcher Watch App
//
//  Created by Codex on 2026-04-12.
//

import SwiftUI

struct WatchAccountRow: View {
    let account: StoredAccount

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(
                AccountsPresentationLogic.displayName(for: account),
                systemImage: AccountIconOption.resolve(from: account.iconSystemName).systemName
            )
            .lineLimit(1)

            HStack(spacing: 6) {
                WatchUsageBadge(title: "7d", value: account.sevenDayLimitUsedPercent)
                WatchUsageBadge(title: "5h", value: account.fiveHourLimitUsedPercent)
            }
            .privacySensitive()
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(AccountsPresentationLogic.displayName(for: account)), " +
            AccountDisplayFormatter.accessibilityUsageListDescription(
                sevenDayRemainingPercent: account.sevenDayLimitUsedPercent,
                fiveHourRemainingPercent: account.fiveHourLimitUsedPercent
            )
        )
    }
}

private struct WatchUsageBadge: View {
    let title: String
    let value: Int?

    var body: some View {
        let percentDescription = AccountDisplayFormatter.compactPercentDescription(value)
        let clampedValue = AccountDisplayFormatter.clampedPercentValue(value) ?? 0
        let color = AccountDisplayFormatter.usageColorComponents(forRemainingPercent: clampedValue)

        Text("\(title) \(percentDescription)")
            .font(.caption2.monospacedDigit())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: 0.16))
            )
    }
}
