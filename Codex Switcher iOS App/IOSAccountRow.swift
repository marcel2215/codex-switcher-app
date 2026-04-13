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
                        title: AccountDisplayFormatter.progressResetLabel(
                            until: account.fiveHourResetsAt,
                            fallbackTitle: "5h"
                        ),
                        remainingPercent: account.fiveHourLimitUsedPercent
                    )

                    IOSRateLimitProgressBar(
                        title: AccountDisplayFormatter.progressResetLabel(
                            until: account.sevenDayResetsAt,
                            fallbackTitle: "7d"
                        ),
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
        let components = AccountDisplayFormatter.adaptiveUsageColorComponents(
            forRemainingPercent: clampedPercent,
            colorScheme: colorScheme,
            contrast: colorSchemeContrast
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
                    .foregroundStyle(.primary)
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
}
