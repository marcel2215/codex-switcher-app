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
            "Name"
        case .dateAdded:
            "Date Added"
        case .lastLogin:
            "Last Login"
        case .rateLimit:
            "Rate Limit"
        case .custom:
            "Custom"
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
            "Ascending"
        case .descending:
            "Descending"
        }
    }
}
