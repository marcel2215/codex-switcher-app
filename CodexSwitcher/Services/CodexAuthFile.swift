//
//  CodexAuthFile.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-07.
//

import CryptoKit
import Foundation

enum CodexAuthFileError: LocalizedError {
    case invalidEncoding
    case invalidJSON
    case missingCredentials

    var errorDescription: String? {
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

enum CodexAuthFile {
    nonisolated static func parse(contents: String) throws -> CodexAuthSnapshot {
        let payload = try decodedPayload(from: contents)

        let authMode = CodexAuthMode(payloadAuthMode: payload.authMode, apiKey: payload.openAIAPIKey)
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
            throw CodexAuthFileError.missingCredentials
        }

        switch authMode {
        case .apiKey:
            guard firstNonEmpty(payload.openAIAPIKey) != nil else {
                throw CodexAuthFileError.missingCredentials
            }
        case .chatgpt, .chatgptAuthTokens:
            guard payload.tokens != nil else {
                throw CodexAuthFileError.missingCredentials
            }
        }

        return CodexAuthSnapshot(
            rawContents: contents,
            identityKey: identityKey,
            authMode: authMode,
            accountIdentifier: accountIdentifier,
            email: email
        )
    }

    nonisolated static func parseRateLimitCredentials(contents: String) throws -> CodexRateLimitCredentials {
        let payload = try decodedPayload(from: contents)
        let authMode = CodexAuthMode(payloadAuthMode: payload.authMode, apiKey: payload.openAIAPIKey)
        let claims = decodeClaims(from: payload.tokens?.idToken ?? payload.tokens?.accessToken)
        let email = firstNonEmpty(
            claims?.email,
            claims?.profile?.email
        )?.lowercased()

        guard let identityKey = stableChatGPTIdentityKey(
            workspaceID: claims?.auth?.chatgptWorkspaceID,
            accountID: firstNonEmpty(payload.tokens?.accountID, claims?.auth?.chatgptAccountID),
            userID: claims?.auth?.chatgptUserID,
            subject: claims?.subject,
            email: email
        ) ?? email.map({ "email:\($0)" }) else {
            throw CodexAuthFileError.missingCredentials
        }

        return CodexRateLimitCredentials(
            identityKey: identityKey,
            authMode: authMode,
            accountID: firstNonEmpty(payload.tokens?.accountID, claims?.auth?.chatgptAccountID),
            accessToken: firstNonEmpty(payload.tokens?.accessToken),
            idToken: firstNonEmpty(payload.tokens?.idToken)
        )
    }

    private nonisolated static func decodedPayload(from contents: String) throws -> Payload {
        guard let data = contents.data(using: .utf8) else {
            throw CodexAuthFileError.invalidEncoding
        }

        do {
            return try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw CodexAuthFileError.invalidJSON
        }
    }

    private nonisolated static func decodeClaims(from token: String?) -> JWTClaims? {
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

        return try? JSONDecoder().decode(JWTClaims.self, from: payloadData)
    }

    private nonisolated static func sha256Hex(for string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // Auth tokens can expose several IDs. Hashing a normalized composite avoids
    // collapsing distinct accounts when any one field is reused or omitted.
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

private extension CodexAuthMode {
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

private nonisolated struct Payload: Decodable {
    let authMode: String?
    let openAIAPIKey: String?
    let tokens: Tokens?

    nonisolated enum CodingKeys: String, CodingKey {
        case authMode = "auth_mode"
        case openAIAPIKey = "OPENAI_API_KEY"
        case tokens
    }
}

private nonisolated struct Tokens: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let idToken: String?
    let accountID: String?

    nonisolated enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
        case accountID = "account_id"
    }
}

private nonisolated struct JWTClaims: Decodable {
    let email: String?
    let profile: ProfileClaims?
    let auth: AuthClaims?
    let subject: String?

    nonisolated enum CodingKeys: String, CodingKey {
        case email
        case profile = "https://api.openai.com/profile"
        case auth = "https://api.openai.com/auth"
        case subject = "sub"
    }
}

private nonisolated struct ProfileClaims: Decodable {
    let email: String?
}

private nonisolated struct AuthClaims: Decodable {
    let chatgptAccountID: String?
    let chatgptUserID: String?
    let chatgptWorkspaceID: String?

    nonisolated enum CodingKeys: String, CodingKey {
        case chatgptAccountID = "chatgpt_account_id"
        case chatgptUserID = "chatgpt_user_id"
        case chatgptWorkspaceID = "chatgpt_workspace_id"
    }
}
