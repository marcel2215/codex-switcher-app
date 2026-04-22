//
//  RateLimitMetricDataStatus.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-12.
//

import Foundation

/// Describes how trustworthy the currently stored rate-limit value is.
/// Widgets use this to decide whether to show the normal semantic tint, keep a
/// gray cached value, or fall back to a missing/unknown placeholder.
enum RateLimitMetricDataStatus: String, Codable, Sendable {
    case exact
    case cached
    case missing
}
