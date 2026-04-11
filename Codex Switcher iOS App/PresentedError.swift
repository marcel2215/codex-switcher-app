//
//  PresentedError.swift
//  Codex Switcher iOS App
//
//  Created by Codex on 2026-04-11.
//

import Foundation

struct PresentedError: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
}
