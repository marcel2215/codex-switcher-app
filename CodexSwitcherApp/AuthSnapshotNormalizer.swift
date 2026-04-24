//
//  AuthSnapshotNormalizer.swift
//  Codex Switcher
//
//  Created by OpenAI on 2026-04-24.
//

import Foundation

enum CodexAuthSnapshotNormalizer {
    private nonisolated static let defaultLegacyLastRefresh = Date(timeIntervalSince1970: 0)

    nonisolated static func normalizedForCodexRuntime(
        _ contents: String,
        defaultLastRefresh: Date = defaultLegacyLastRefresh
    ) throws -> String {
        guard let data = contents.data(using: .utf8) else {
            throw CodexAuthSnapshotNormalizationError.invalidEncoding
        }

        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        guard var payload = jsonObject as? [String: Any] else {
            return contents
        }

        guard shouldNormalizeChatGPTPayload(payload) else {
            return contents
        }

        var didChange = false
        if payload["auth_mode"] == nil {
            payload["auth_mode"] = CodexAuthMode.chatgpt.rawValue
            didChange = true
        }

        if !payload.keys.contains("OPENAI_API_KEY") {
            payload["OPENAI_API_KEY"] = NSNull()
            didChange = true
        }

        if needsLastRefresh(payload["last_refresh"]) {
            payload["last_refresh"] = iso8601Timestamp(from: defaultLastRefresh)
            didChange = true
        }

        guard didChange else {
            return contents
        }

        let normalizedData = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        )
        guard let normalizedContents = String(data: normalizedData, encoding: .utf8) else {
            throw CodexAuthSnapshotNormalizationError.invalidEncoding
        }

        return normalizedContents
    }

    private nonisolated static func shouldNormalizeChatGPTPayload(_ payload: [String: Any]) -> Bool {
        guard payload["tokens"] is [String: Any] else {
            return false
        }

        guard let rawAuthMode = payload["auth_mode"] as? String else {
            return payload["OPENAI_API_KEY"] == nil || payload["OPENAI_API_KEY"] is NSNull
        }

        return rawAuthMode == CodexAuthMode.chatgpt.rawValue
    }

    private nonisolated static func needsLastRefresh(_ value: Any?) -> Bool {
        switch value {
        case nil:
            return true
        case is NSNull:
            return true
        case let string as String:
            return string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:
            return false
        }
    }

    nonisolated static func iso8601Timestamp(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}

enum CodexAuthSnapshotNormalizationError: LocalizedError {
    case invalidEncoding

    nonisolated var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            return "Codex auth.json isn't encoded as valid UTF-8 text."
        }
    }
}
