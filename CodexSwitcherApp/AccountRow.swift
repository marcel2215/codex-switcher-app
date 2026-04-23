//
//  AccountRow.swift
//  Codex Switcher
//
//  Created by Marcel Kwiatkowski on 2026-04-11.
//

import SwiftUI

struct IOSAccountRow: View {
    let account: StoredAccount
    let exportTransferItem: CodexAccountArchiveTransferItem?
    let archiveAvailabilityRefreshToken: Int

    @State private var isArchiveExportAvailable = false

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
                        fallbackTitle: "5h",
                        resetAt: account.fiveHourResetsAt,
                        remainingPercent: account.fiveHourLimitUsedPercent
                    )

                    IOSRateLimitProgressBar(
                        fallbackTitle: "7d",
                        resetAt: account.sevenDayResetsAt,
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
        .modifier(AccountArchiveDragModifier(transferItem: exportTransferItem, isAvailable: isArchiveExportAvailable))
        .task(id: exportAvailabilityTaskKey) {
            isArchiveExportAvailable = await exportTransferItem?.canExport() ?? false
        }
    }

    private var exportAvailabilityTaskKey: String {
        "\(exportTransferItem?.availabilityKey ?? "none")|\(archiveAvailabilityRefreshToken)"
    }
}

private struct AccountArchiveDragModifier: ViewModifier {
    let transferItem: CodexAccountArchiveTransferItem?
    let isAvailable: Bool

    func body(content: Content) -> some View {
        guard let transferItem, isAvailable else {
            return AnyView(content)
        }

        return AnyView(content.draggable(transferItem))
    }
}

private struct IOSRateLimitProgressBar: View {
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
