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
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: AccountIconOption.resolve(from: account.iconSystemName).systemName)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 6) {
                Text(AccountsPresentationLogic.displayName(for: account))
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                WatchRateLimitProgressBar(
                    fallbackTitle: "5h",
                    resetAt: account.fiveHourResetsAt,
                    remainingPercent: account.fiveHourLimitUsedPercent
                )

                WatchRateLimitProgressBar(
                    fallbackTitle: "7d",
                    resetAt: account.sevenDayResetsAt,
                    remainingPercent: account.sevenDayLimitUsedPercent
                )
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(AccountsPresentationLogic.displayName(for: account)), \(AccountDisplayFormatter.accessibilityUsageListDescription(sevenDayRemainingPercent: account.sevenDayLimitUsedPercent, fiveHourRemainingPercent: account.fiveHourLimitUsedPercent))"
        )
    }
}

private struct WatchRateLimitProgressBar: View {
    let fallbackTitle: String
    let resetAt: Date?
    let remainingPercent: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                RateLimitResetText(
                    resetAt: resetAt,
                    fallbackText: fallbackTitle
                )
                    .monospacedDigit()
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Text(AccountDisplayFormatter.compactPercentDescription(remainingPercent))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.primary)
            }

            RateLimitLinearProgressBar(
                remainingPercent: remainingPercent,
                height: 4,
                trackOpacity: 0.25
            )
            .frame(maxWidth: .infinity)
        }
    }
}
