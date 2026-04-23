//
//  PresentedError.swift
//  Codex Switcher
//
//  Created by Marcel Kwiatkowski on 2026-04-12.
//

import Foundation

struct PresentedError: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
}
