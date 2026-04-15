//
//  IOSAccountRow.swift
//  Codex Switcher iOS App
//
//  Created by Codex on 2026-04-11.
//

import SwiftUI

struct IOSAccountRow: View {
    let account: StoredAccount
    let exportTransferItem: CodexAccountArchiveTransferItem?

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
        .modifier(AccountArchiveDragModifier(transferItem: exportTransferItem, isAvailable: isArchiveExportAvailable))
        .task(id: exportTransferItem?.availabilityKey) {
            isArchiveExportAvailable = await exportTransferItem?.canExport() ?? false
        }
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
    let title: String
    let remainingPercent: Int?

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

            RateLimitLinearProgressBar(
                remainingPercent: remainingPercent,
                height: 4,
                trackOpacity: 0.25
            )
            .frame(maxWidth: .infinity)
        }
    }
}
