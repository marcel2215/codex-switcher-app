//
//  RateLimitRequestLimiter.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-11.
//

import Foundation

actor CodexRateLimitRequestLimiter {
    private let maxRequestsPerMinute: Int
    private let minimumSpacing: TimeInterval
    private var recentRequests: [Date] = []

    init(maxRequestsPerMinute: Int, minimumSpacing: TimeInterval) {
        self.maxRequestsPerMinute = maxRequestsPerMinute
        self.minimumSpacing = minimumSpacing
    }

    func acquire() async throws {
        while true {
            try Task.checkCancellation()

            let now = Date()
            recentRequests.removeAll { now.timeIntervalSince($0) >= 60 }

            let spacingWait = max(
                recentRequests.last?.addingTimeInterval(minimumSpacing).timeIntervalSince(now) ?? 0,
                0
            )
            let volumeWait: TimeInterval
            if recentRequests.count < maxRequestsPerMinute {
                volumeWait = 0
            } else {
                volumeWait = max(
                    recentRequests.first?.addingTimeInterval(60).timeIntervalSince(now) ?? 0,
                    0
                )
            }
            let sleepSeconds = max(spacingWait, volumeWait)

            if sleepSeconds <= 0 {
                recentRequests.append(now)
                return
            }

            try await Task.sleep(for: .seconds(sleepSeconds))
        }
    }
}
