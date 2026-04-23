//
//  HomeScreenQuickActionAccountItem.swift
//  Codex Switcher
//
//  Created by Marcel Kwiatkowski on 2026-04-14.
//

import Foundation

struct IOSHomeScreenQuickActionAccountItem: Equatable, Sendable {
    let id: UUID
    let title: String
    let subtitle: String?
    let iconSystemName: String
}
