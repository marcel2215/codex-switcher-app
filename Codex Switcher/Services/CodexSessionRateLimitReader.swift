//
//  CodexSessionRateLimitReader.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-09.
//

import Foundation

nonisolated struct CodexRateLimitObservation: Sendable, Equatable {
    let observedAt: Date
    let sevenDayUsedPercent: Int?
    let fiveHourUsedPercent: Int?
}

struct CodexSessionRateLimitReader: Sendable {
    private nonisolated static let maximumSessionFilesToInspect = 5
    private nonisolated static let maximumTailBytesToInspect = 512 * 1_024

    /// Reads the newest Codex session telemetry from the linked `.codex` folder.
    /// This is intentionally best-effort: failures return `nil` so the UI can
    /// fall back to `?` instead of surfacing unrelated filesystem errors.
    nonisolated func readLatestObservation(in linkedFolderURL: URL, authFileURL: URL) async -> CodexRateLimitObservation? {
        await Task.detached(priority: .utility) {
            readLatestObservationSynchronously(in: linkedFolderURL, authFileURL: authFileURL)
        }.value
    }

    private nonisolated func readLatestObservationSynchronously(in linkedFolderURL: URL, authFileURL: URL) -> CodexRateLimitObservation? {
        let startedAccess = linkedFolderURL.startAccessingSecurityScopedResource()
        defer {
            if startedAccess {
                linkedFolderURL.stopAccessingSecurityScopedResource()
            }
        }

        let sessionsDirectoryURL = linkedFolderURL.appending(path: "sessions", directoryHint: .isDirectory)

        guard let sessionFiles = newestSessionFiles(in: sessionsDirectoryURL), !sessionFiles.isEmpty else {
            return nil
        }

        for sessionFileURL in sessionFiles {
            guard let observation = newestObservation(in: sessionFileURL) else {
                continue
            }

            guard observation.sevenDayUsedPercent != nil || observation.fiveHourUsedPercent != nil else {
                continue
            }

            return observation
        }

        return nil
    }

    private nonisolated func newestSessionFiles(in sessionsDirectoryURL: URL) -> [URL]? {
        guard let enumerator = FileManager.default.enumerator(
            at: sessionsDirectoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let sessionFiles = enumerator.compactMap { element -> (url: URL, modifiedAt: Date)? in
            guard
                let fileURL = element as? URL,
                fileURL.pathExtension == "jsonl",
                let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]),
                resourceValues.isRegularFile == true,
                let modifiedAt = resourceValues.contentModificationDate
            else {
                return nil
            }

            return (fileURL, modifiedAt)
        }

        return sessionFiles
            .sorted { lhs, rhs in
                if lhs.modifiedAt != rhs.modifiedAt {
                    return lhs.modifiedAt > rhs.modifiedAt
                }

                return lhs.url.lastPathComponent > rhs.url.lastPathComponent
            }
            .prefix(Self.maximumSessionFilesToInspect)
            .map(\.url)
    }

    private nonisolated func newestObservation(in sessionFileURL: URL) -> CodexRateLimitObservation? {
        guard let tail = readTail(of: sessionFileURL), !tail.isEmpty else {
            return nil
        }

        for line in tail.split(whereSeparator: \.isNewline).reversed() {
            guard let observation = observation(from: line) else {
                continue
            }

            return observation
        }

        return nil
    }

    private nonisolated func observation(from line: Substring) -> CodexRateLimitObservation? {
        guard let data = line.data(using: .utf8) else {
            return nil
        }

        let decoder = JSONDecoder()
        guard let event = try? decoder.decode(CodexSessionEvent.self, from: data) else {
            return nil
        }

        guard event.type == "event_msg", event.payload.type == "token_count" else {
            return nil
        }

        let observedAt = Self.parseSessionTimestamp(event.timestamp)
        let rateLimits = event.payload.info?.rateLimits ?? event.payload.rateLimits
        let windows = [rateLimits?.primary, rateLimits?.secondary]

        var sevenDayUsedPercent: Int?
        var fiveHourUsedPercent: Int?

        for window in windows {
            guard
                let window,
                let windowMinutes = window.windowMinutes,
                let usedPercent = clampedUsedPercent(from: window.usedPercent)
            else {
                continue
            }

            switch windowMinutes {
            case 300:
                fiveHourUsedPercent = usedPercent
            case 10_080:
                sevenDayUsedPercent = usedPercent
            default:
                continue
            }
        }

        guard sevenDayUsedPercent != nil || fiveHourUsedPercent != nil else {
            return nil
        }

        return CodexRateLimitObservation(
            observedAt: observedAt,
            sevenDayUsedPercent: sevenDayUsedPercent,
            fiveHourUsedPercent: fiveHourUsedPercent
        )
    }

    // Session files can grow very large, so read only the tail where the most
    // recent token_count events live. This keeps account switching responsive.
    private nonisolated func readTail(of sessionFileURL: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: sessionFileURL) else {
            return nil
        }

        defer {
            try? handle.close()
        }

        guard let fileSize = try? handle.seekToEnd() else {
            return nil
        }

        let byteCount = min(Int(fileSize), Self.maximumTailBytesToInspect)
        let startOffset = max(Int64(fileSize) - Int64(byteCount), 0)

        do {
            try handle.seek(toOffset: UInt64(startOffset))
            guard let data = try handle.read(upToCount: byteCount), !data.isEmpty else {
                return nil
            }

            return String(decoding: data, as: UTF8.self)
        } catch {
            return nil
        }
    }

    private nonisolated func clampedUsedPercent(from value: Double?) -> Int? {
        guard let value, value.isFinite else {
            return nil
        }

        return min(max(Int(value.rounded()), 0), 100)
    }

    private nonisolated static func parseSessionTimestamp(_ value: String) -> Date {
        let fractionalSecondsFormatter = ISO8601DateFormatter()
        fractionalSecondsFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let fractionalSecondsDate = fractionalSecondsFormatter.date(from: value) {
            return fractionalSecondsDate
        }

        let standardFormatter = ISO8601DateFormatter()
        standardFormatter.formatOptions = [.withInternetDateTime]
        if let standardDate = standardFormatter.date(from: value) {
            return standardDate
        }

        return .distantPast
    }

}

private nonisolated struct CodexSessionEvent: Decodable {
    let timestamp: String
    let type: String
    let payload: CodexSessionPayload
}

private nonisolated struct CodexSessionPayload: Decodable {
    let type: String
    let info: CodexSessionInfo?
    let rateLimits: CodexSessionRateLimits?

    enum CodingKeys: String, CodingKey {
        case type
        case info
        case rateLimits = "rate_limits"
    }
}

private nonisolated struct CodexSessionInfo: Decodable {
    let rateLimits: CodexSessionRateLimits

    enum CodingKeys: String, CodingKey {
        case rateLimits = "rate_limits"
    }
}

private nonisolated struct CodexSessionRateLimits: Decodable {
    let primary: CodexSessionRateLimitWindow?
    let secondary: CodexSessionRateLimitWindow?
}

private nonisolated struct CodexSessionRateLimitWindow: Decodable {
    let usedPercent: Double?
    let windowMinutes: Int?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case windowMinutes = "window_minutes"
    }
}
