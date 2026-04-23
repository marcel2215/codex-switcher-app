//
//  SharedAuthFile.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-08.
//

import CryptoKit
import Foundation

nonisolated enum SharedCodexAuthMode: String, Sendable {
    case apiKey
    case chatgpt
    case chatgptAuthTokens
}

nonisolated struct SharedCodexAuthSnapshot: Sendable, Equatable {
    let rawContents: String
    let identityKey: String
    let authMode: SharedCodexAuthMode
    let accountIdentifier: String?
    let email: String?
}

nonisolated enum SharedCodexAuthFileError: LocalizedError {
    case invalidEncoding
    case invalidJSON
    case missingCredentials

    nonisolated var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            "Codex auth.json isn't encoded as valid UTF-8 text."
        case .invalidJSON:
            "Codex auth.json doesn't contain valid JSON."
        case .missingCredentials:
            "Codex auth.json doesn't contain a supported account payload."
        }
    }
}

enum SharedCodexAuthFile {
    nonisolated static func parse(contents: String) throws -> SharedCodexAuthSnapshot {
        guard let data = contents.data(using: .utf8) else {
            throw SharedCodexAuthFileError.invalidEncoding
        }

        let decoder = JSONDecoder()

        let payload: SharedCodexPayload
        do {
            payload = try decoder.decode(SharedCodexPayload.self, from: data)
        } catch {
            throw SharedCodexAuthFileError.invalidJSON
        }

        let authMode = SharedCodexAuthMode(payloadAuthMode: payload.authMode, apiKey: payload.openAIAPIKey)
        let claims = decodeClaims(from: payload.tokens?.idToken ?? payload.tokens?.accessToken)
        let accountIdentifier = firstNonEmpty(
            claims?.auth?.chatgptWorkspaceID,
            payload.tokens?.accountID,
            claims?.auth?.chatgptAccountID,
            claims?.auth?.chatgptUserID,
            claims?.subject
        )
        let email = firstNonEmpty(
            claims?.email,
            claims?.profile?.email
        )?.lowercased()

        let identityKey: String
        if let chatGPTIdentityKey = stableChatGPTIdentityKey(
            workspaceID: claims?.auth?.chatgptWorkspaceID,
            accountID: firstNonEmpty(payload.tokens?.accountID, claims?.auth?.chatgptAccountID),
            userID: claims?.auth?.chatgptUserID,
            subject: claims?.subject,
            email: email
        ) {
            identityKey = chatGPTIdentityKey
        } else if let email {
            identityKey = "email:\(email)"
        } else if let apiKey = firstNonEmpty(payload.openAIAPIKey) {
            identityKey = "api-key:\(sha256Hex(for: apiKey))"
        } else {
            throw SharedCodexAuthFileError.missingCredentials
        }

        switch authMode {
        case .apiKey:
            guard firstNonEmpty(payload.openAIAPIKey) != nil else {
                throw SharedCodexAuthFileError.missingCredentials
            }
        case .chatgpt, .chatgptAuthTokens:
            guard payload.tokens != nil else {
                throw SharedCodexAuthFileError.missingCredentials
            }
        }

        return SharedCodexAuthSnapshot(
            rawContents: contents,
            identityKey: identityKey,
            authMode: authMode,
            accountIdentifier: accountIdentifier,
            email: email
        )
    }

    private nonisolated static func decodeClaims(from token: String?) -> SharedCodexJWTClaims? {
        guard
            let token,
            !token.isEmpty,
            let payloadSegment = token.split(separator: ".").dropFirst().first
        else {
            return nil
        }

        var encoded = String(payloadSegment)
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let remainder = encoded.count % 4
        if remainder != 0 {
            encoded += String(repeating: "=", count: 4 - remainder)
        }

        guard let payloadData = Data(base64Encoded: encoded) else {
            return nil
        }

        return try? JSONDecoder().decode(SharedCodexJWTClaims.self, from: payloadData)
    }

    private nonisolated static func sha256Hex(for string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static func stableChatGPTIdentityKey(
        workspaceID: String?,
        accountID: String?,
        userID: String?,
        subject: String?,
        email: String?
    ) -> String? {
        let normalizedComponents = [
            ("workspace", workspaceID),
            ("account", accountID),
            ("user", userID),
            ("subject", subject),
            ("email", email),
        ].compactMap { label, value -> String? in
            guard let normalizedValue = normalizedIdentityValue(value) else {
                return nil
            }

            return "\(label)=\(normalizedValue)"
        }

        guard !normalizedComponents.isEmpty else {
            return nil
        }

        return "chatgpt:\(sha256Hex(for: normalizedComponents.joined(separator: "|")))"
    }

    private nonisolated static func normalizedIdentityValue(_ value: String?) -> String? {
        guard let value = firstNonEmpty(value) else {
            return nil
        }

        return value.lowercased()
    }

    private nonisolated static func firstNonEmpty(_ values: String?...) -> String? {
        values.first { value in
            guard let value else {
                return false
            }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ?? nil
    }
}

private extension SharedCodexAuthMode {
    nonisolated init(payloadAuthMode: String?, apiKey: String?) {
        switch payloadAuthMode {
        case Self.apiKey.rawValue:
            self = .apiKey
        case Self.chatgptAuthTokens.rawValue:
            self = .chatgptAuthTokens
        case Self.chatgpt.rawValue:
            self = .chatgpt
        default:
            self = firstNonEmpty(apiKey) == nil ? .chatgpt : .apiKey
        }
    }
}

private nonisolated func firstNonEmpty(_ values: String?...) -> String? {
    values.first { value in
        guard let value else {
            return false
        }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    } ?? nil
}

private nonisolated struct SharedCodexPayload: Decodable {
    let authMode: String?
    let openAIAPIKey: String?
    let tokens: SharedCodexTokens?

    enum CodingKeys: String, CodingKey {
        case authMode = "auth_mode"
        case openAIAPIKey = "OPENAI_API_KEY"
        case tokens
    }
}

private nonisolated struct SharedCodexTokens: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let idToken: String?
    let accountID: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
        case accountID = "account_id"
    }
}

private nonisolated struct SharedCodexJWTClaims: Decodable {
    let email: String?
    let profile: SharedCodexProfileClaims?
    let auth: SharedCodexAuthClaims?
    let subject: String?

    enum CodingKeys: String, CodingKey {
        case email
        case profile = "https://api.openai.com/profile"
        case auth = "https://api.openai.com/auth"
        case subject = "sub"
    }
}

private nonisolated struct SharedCodexProfileClaims: Decodable {
    let email: String?
}

private nonisolated struct SharedCodexAuthClaims: Decodable {
    let chatgptAccountID: String?
    let chatgptUserID: String?
    let chatgptWorkspaceID: String?

    enum CodingKeys: String, CodingKey {
        case chatgptAccountID = "chatgpt_account_id"
        case chatgptUserID = "chatgpt_user_id"
        case chatgptWorkspaceID = "chatgpt_workspace_id"
    }
}
