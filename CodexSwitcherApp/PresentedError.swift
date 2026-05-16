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

    init(title: String, message: String) {
        self.title = L10n.string(title, comment: "Alert title.")
        self.message = L10n.string(message, comment: "Alert message.")
    }
}
