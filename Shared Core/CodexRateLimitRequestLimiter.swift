//
//  CodexRateLimitRequestLimiter.swift
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

    func acquire() async {
        while true {
            let now = Date()
            recentRequests.removeAll { now.timeIntervalSince($0) >= 60 }

            let spacingSatisfied = recentRequests.last.map { now.timeIntervalSince($0) >= minimumSpacing } ?? true
            let volumeSatisfied = recentRequests.count < maxRequestsPerMinute

            if spacingSatisfied, volumeSatisfied {
                recentRequests.append(now)
                return
            }

            try? await Task.sleep(for: .milliseconds(750))
        }
    }
}
