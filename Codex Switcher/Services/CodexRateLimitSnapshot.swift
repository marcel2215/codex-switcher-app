//
//  CodexRateLimitSnapshot.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-09.
//

import Foundation

nonisolated enum CodexRateLimitSource: String, Sendable, Equatable {
    case remoteUsageAPI
    case sessionLogFallback

    var priority: Int {
        switch self {
        case .remoteUsageAPI:
            2
        case .sessionLogFallback:
            1
        }
    }
}

nonisolated struct CodexRateLimitSnapshot: Sendable, Equatable {
    let identityKey: String
    let observedAt: Date
    let fetchedAt: Date
    let source: CodexRateLimitSource
    let sevenDayRemainingPercent: Int?
    let fiveHourRemainingPercent: Int?
    let sevenDayResetsAt: Date?
    let fiveHourResetsAt: Date?

    var nextResetAt: Date? {
        [fiveHourResetsAt, sevenDayResetsAt].compactMap { $0 }.min()
    }

    func applyingResetBoundaries(relativeTo now: Date = .now) -> CodexRateLimitSnapshot {
        CodexRateLimitSnapshot(
            identityKey: identityKey,
            observedAt: observedAt,
            fetchedAt: fetchedAt,
            source: source,
            sevenDayRemainingPercent: Self.adjustedRemainingPercent(
                sevenDayRemainingPercent,
                resetsAt: sevenDayResetsAt,
                relativeTo: now
            ),
            fiveHourRemainingPercent: Self.adjustedRemainingPercent(
                fiveHourRemainingPercent,
                resetsAt: fiveHourResetsAt,
                relativeTo: now
            ),
            sevenDayResetsAt: sevenDayResetsAt,
            fiveHourResetsAt: fiveHourResetsAt
        )
    }

    private static func adjustedRemainingPercent(
        _ value: Int?,
        resetsAt: Date?,
        relativeTo now: Date
    ) -> Int? {
        guard let value else {
            return nil
        }

        if let resetsAt, now >= resetsAt {
            return 100
        }

        return min(max(value, 0), 100)
    }
}
