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
                Text(account.name)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(AccountDisplayFormatter.listMetadataDescription(
                    lastLoginAt: account.lastLoginAt,
                    sevenDayRemainingPercent: account.sevenDayLimitUsedPercent,
                    fiveHourRemainingPercent: account.fiveHourLimitUsedPercent
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .accessibilityLabel(AccountDisplayFormatter.accessibilityMetadataDescription(
                    lastLoginAt: account.lastLoginAt,
                    sevenDayRemainingPercent: account.sevenDayLimitUsedPercent,
                    fiveHourRemainingPercent: account.fiveHourLimitUsedPercent
                ))
            }
        }
        .padding(.vertical, 4)
    }
}
