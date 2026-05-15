//
//  AccountSortOptions.swift
//  Codex Switcher
//
//  Created by Marcel Kwiatkowski on 2026-04-07.
//

import Foundation

enum AccountSortCriterion: String, CaseIterable, Identifiable, Codable, Sendable {
    case name
    case dateAdded
    case lastLogin
    case rateLimit
    case custom

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .name:
            L10n.string("sort.criterion.name", defaultValue: "Name")
        case .dateAdded:
            L10n.string("sort.criterion.dateAdded", defaultValue: "Date Added")
        case .lastLogin:
            L10n.string("sort.criterion.lastLogin", defaultValue: "Last Login")
        case .rateLimit:
            L10n.string("sort.criterion.rateLimit", defaultValue: "Rate Limit")
        case .custom:
            L10n.string("sort.criterion.custom", defaultValue: "Custom")
        }
    }
}

enum SortDirection: String, CaseIterable, Identifiable, Codable, Sendable {
    case ascending
    case descending

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .ascending:
            L10n.string("sort.direction.ascending", defaultValue: "Ascending")
        case .descending:
            L10n.string("sort.direction.descending", defaultValue: "Descending")
        }
    }
}
