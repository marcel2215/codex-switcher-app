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

        var didChange = account.normalizeLegacyLocalOnlyFields()

        if account.rateLimitsObservedAt != adjustedSnapshot.observedAt {
            account.rateLimitsObservedAt = adjustedSnapshot.observedAt
            didChange = true
        }

        if account.sevenDayLimitUsedPercent != adjustedSnapshot.sevenDayRemainingPercent {
            if let sevenDayRemainingPercent = adjustedSnapshot.sevenDayRemainingPercent {
                account.sevenDayLimitUsedPercent = sevenDayRemainingPercent
                didChange = true
            }
        }

        if account.fiveHourLimitUsedPercent != adjustedSnapshot.fiveHourRemainingPercent {
            if let fiveHourRemainingPercent = adjustedSnapshot.fiveHourRemainingPercent {
                account.fiveHourLimitUsedPercent = fiveHourRemainingPercent
                didChange = true
            }
        }

        let sevenDayStatus: RateLimitMetricDataStatus = if adjustedSnapshot.sevenDayRemainingPercent != nil {
            .exact
        } else if account.sevenDayLimitUsedPercent != nil {
            .cached
        } else {
            .missing
        }

        if account.sevenDayDataStatus != sevenDayStatus {
            account.sevenDayDataStatus = sevenDayStatus
            didChange = true
        }

        let fiveHourStatus: RateLimitMetricDataStatus = if adjustedSnapshot.fiveHourRemainingPercent != nil {
            .exact
        } else if account.fiveHourLimitUsedPercent != nil {
            .cached
        } else {
            .missing
        }

        if account.fiveHourDataStatus != fiveHourStatus {
            account.fiveHourDataStatus = fiveHourStatus
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
