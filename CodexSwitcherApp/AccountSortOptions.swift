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
            L10n.string("Name", comment: "Display label for Name.")
        case .dateAdded:
            L10n.string("Date Added", comment: "Display label for Date Added.")
        case .lastLogin:
            L10n.string("Last Login", comment: "Display label for Last Login.")
        case .rateLimit:
            L10n.string("Rate Limit", comment: "Display label for Rate Limit.")
        case .custom:
            L10n.string("Custom", comment: "Display label for Custom.")
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
            L10n.string("Ascending", comment: "Display label for Ascending.")
        case .descending:
            L10n.string("Descending", comment: "Display label for Descending.")
        }
    }
}
