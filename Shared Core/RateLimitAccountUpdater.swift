//
//  RateLimitAccountUpdater.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-11.
//

import Foundation

enum RateLimitAccountUpdater {
    nonisolated static let currentDisplayVersion = 1

    @MainActor
    @discardableResult
    static func apply(_ snapshot: CodexRateLimitSnapshot, to account: StoredAccount) -> Bool {
        let adjustedSnapshot = snapshot.applyingResetBoundaries()
        let existingObservedAt = account.rateLimitsObservedAt ?? .distantPast

        guard adjustedSnapshot.observedAt >= existingObservedAt else {
            return false
        }

        var didChange = false

        if account.rateLimitsObservedAt != adjustedSnapshot.observedAt {
            account.rateLimitsObservedAt = adjustedSnapshot.observedAt
            didChange = true
        }

        if account.sevenDayLimitUsedPercent != adjustedSnapshot.sevenDayRemainingPercent {
            account.sevenDayLimitUsedPercent = adjustedSnapshot.sevenDayRemainingPercent
            didChange = true
        }

        if account.fiveHourLimitUsedPercent != adjustedSnapshot.fiveHourRemainingPercent {
            account.fiveHourLimitUsedPercent = adjustedSnapshot.fiveHourRemainingPercent
            didChange = true
        }

        if account.sevenDayResetsAt != adjustedSnapshot.sevenDayResetsAt {
            account.sevenDayResetsAt = adjustedSnapshot.sevenDayResetsAt
            didChange = true
        }

        if account.fiveHourResetsAt != adjustedSnapshot.fiveHourResetsAt {
            account.fiveHourResetsAt = adjustedSnapshot.fiveHourResetsAt
            didChange = true
        }

        if account.rateLimitDisplayVersion != currentDisplayVersion {
            account.rateLimitDisplayVersion = currentDisplayVersion
            didChange = true
        }

        return didChange
    }

    @MainActor
    @discardableResult
    static func apply(
        _ observation: CodexRateLimitObservation,
        identityKey: String,
        to account: StoredAccount
    ) -> Bool {
        apply(
            CodexRateLimitSnapshot(
                identityKey: identityKey,
                observedAt: observation.observedAt,
                fetchedAt: .now,
                source: .sessionLogFallback,
                sevenDayRemainingPercent: observation.sevenDayRemainingPercent,
                fiveHourRemainingPercent: observation.fiveHourRemainingPercent,
                sevenDayResetsAt: observation.sevenDayResetsAt,
                fiveHourResetsAt: observation.fiveHourResetsAt
            ),
            to: account
        )
    }
}
