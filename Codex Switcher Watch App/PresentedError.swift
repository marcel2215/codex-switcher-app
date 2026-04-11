//
//  PresentedError.swift
//  Codex Switcher Watch App
//
//  Created by Codex on 2026-04-12.
//

import Foundation

struct PresentedError: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
}
