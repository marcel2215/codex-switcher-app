//
//  CodexLocalization.swift
//  Codex Switcher
//
//  Created by Codex on 2026-05-15.
//

import Foundation

enum L10n {
    nonisolated static func string(
        _ key: String,
        defaultValue: String,
        _ arguments: CVarArg...
    ) -> String {
        let format = localizedFormat(for: key, defaultValue: defaultValue)
        guard !arguments.isEmpty else {
            return format
        }

        return String(format: format, locale: .current, arguments: arguments)
    }

    nonisolated static func localizedFormat(for key: String, defaultValue: String) -> String {
        Bundle.main.localizedString(forKey: key, value: defaultValue, table: nil)
    }
}
