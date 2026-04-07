//
//  AccountIconOption.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-07.
//

import Foundation

enum AccountIconOption: String, CaseIterable, Identifiable, Sendable {
    case key = "key.fill"
    case person = "person.crop.circle.fill"
    case briefcase = "briefcase.fill"
    case building = "building.2.fill"
    case terminal = "terminal.fill"
    case shield = "shield.fill"
    case bolt = "bolt.fill"
    case star = "star.fill"

    var id: String { rawValue }

    var systemName: String { rawValue }

    var title: String {
        switch self {
        case .key:
            "Key"
        case .person:
            "Person"
        case .briefcase:
            "Briefcase"
        case .building:
            "Building"
        case .terminal:
            "Terminal"
        case .shield:
            "Shield"
        case .bolt:
            "Bolt"
        case .star:
            "Star"
        }
    }

    static let defaultOption: Self = .key

    static func resolve(from storedSystemName: String) -> Self {
        Self(rawValue: storedSystemName) ?? defaultOption
    }
}
