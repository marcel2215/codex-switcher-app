//
//  AppProcessIdentity.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-10.
//

import Foundation

#if canImport(AppKit)
import AppKit
#endif

struct CodexSharedAppProcessIdentity: Codable, Equatable, Hashable, Sendable {
    let processIdentifier: Int32
    let launchDate: Date?

    nonisolated init(processIdentifier: Int32, launchDate: Date?) {
        self.processIdentifier = processIdentifier
        self.launchDate = launchDate
    }

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.processIdentifier == rhs.processIdentifier
            && lhs.launchDate == rhs.launchDate
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(processIdentifier)
        hasher.combine(launchDate)
    }

    /// LaunchServices launch dates are the most reliable ordering signal.
    /// When either side does not have one, fall back to pid ordering so
    /// concurrent launches still converge on one surviving instance.
    nonisolated func wasLaunchedBefore(_ other: Self) -> Bool {
        if
            let launchDate,
            let otherLaunchDate = other.launchDate,
            launchDate != otherLaunchDate
        {
            return launchDate < otherLaunchDate
        }

        return processIdentifier < other.processIdentifier
    }
}

#if canImport(AppKit)
extension CodexSharedAppProcessIdentity {
    nonisolated init(runningApplication: NSRunningApplication) {
        self.init(
            processIdentifier: runningApplication.processIdentifier,
            launchDate: runningApplication.launchDate
        )
    }

    nonisolated static var current: Self {
        Self(runningApplication: .current)
    }
}
#endif
