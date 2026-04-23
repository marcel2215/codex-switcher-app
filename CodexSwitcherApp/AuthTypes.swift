//
//  AuthTypes.swift
//  Codex Switcher
//
//  Created by Marcel Kwiatkowski on 2026-04-11.
//

import Foundation

nonisolated enum CodexAuthMode: String, Sendable {
    case apiKey
    case chatgpt
    case chatgptAuthTokens
}

nonisolated struct CodexAuthSnapshot: Sendable, Equatable {
    let rawContents: String
    let identityKey: String
    let authMode: CodexAuthMode
    let accountIdentifier: String?
    let email: String?
}

nonisolated struct CodexRateLimitCredentials: Sendable, Equatable {
    let identityKey: String
    let authMode: CodexAuthMode
    let accountID: String?
    let accessToken: String?
    let idToken: String?
}
