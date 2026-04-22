//
//  MenuBarIconOption.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-09.
//

import Foundation

enum MenuBarIconOption: String, CaseIterable, Identifiable, Sendable {
    case switcher = "arrow.left.arrow.right"
    case keyCard = "key.card.fill"
    case key = "key.fill"
    case personBadgeKey = "person.badge.key.fill"
    case person = "person.crop.circle.fill"
    case briefcase = "briefcase.fill"
    case house = "house.fill"
    case terminal = "terminal.fill"
    case shield = "shield.fill"
    case lock = "lock.shield.fill"
    case star = "star.fill"
    case heart = "heart.fill"
    case bolt = "bolt.fill"
    case globe = "globe"
    case cloud = "cloud.fill"
    case bell = "bell.fill"
    case bookmark = "bookmark.fill"

    var id: String { rawValue }

    var systemName: String { rawValue }

    var title: String {
        switch self {
        case .switcher:
            "Switch"
        default:
            AccountIconOption.resolve(from: rawValue).title
        }
    }

    static let defaultOption: Self = .switcher

    static func resolve(from storedSystemName: String) -> Self {
        Self(rawValue: storedSystemName) ?? defaultOption
    }
}
