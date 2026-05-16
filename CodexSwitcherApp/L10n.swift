//
//  L10n.swift
//  Codex Switcher
//
//  Created by OpenAI on 2026-05-15.
//

import Foundation

enum L10n {
    nonisolated static func string(_ key: String, comment: String = "") -> String {
        Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }

    nonisolated static func format(_ key: String, _ arguments: CVarArg..., comment: String = "") -> String {
        String(
            format: string(key, comment: comment),
            locale: Locale.current,
            arguments: arguments
        )
    }
}
