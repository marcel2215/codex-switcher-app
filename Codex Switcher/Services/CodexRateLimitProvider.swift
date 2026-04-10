//
//  CodexRateLimitProvider.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-09.
//

import Foundation

struct CodexRateLimitRequest: Sendable {
    let identityKey: String
    let authFileContents: String?
    let linkedLocation: AuthLinkedLocation?
    let isCurrentAccount: Bool
}

protocol CodexRateLimitProviding: Sendable {
    func fetchSnapshot(for request: CodexRateLimitRequest) async -> CodexRateLimitSnapshot?
}

actor CodexRateLimitProvider: CodexRateLimitProviding {
    private nonisolated static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    private let sessionReader: CodexSessionRateLimitReader
    private let requestLimiter: CodexRateLimitRequestLimiter
    private let urlSession: URLSession

    init(
        sessionReader: CodexSessionRateLimitReader = CodexSessionRateLimitReader(),
        requestLimiter: CodexRateLimitRequestLimiter = CodexRateLimitRequestLimiter(
            maxRequestsPerMinute: 8,
            minimumSpacing: 1.5
        ),
        urlSession: URLSession? = nil
    ) {
        self.sessionReader = sessionReader
        self.requestLimiter = requestLimiter

        if let urlSession {
            self.urlSession = urlSession
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.waitsForConnectivity = false
            configuration.timeoutIntervalForRequest = 8
            configuration.timeoutIntervalForResource = 12
            configuration.httpAdditionalHeaders = [
                "Accept": "application/json",
                "User-Agent": "Codex Switcher",
            ]
            self.urlSession = URLSession(configuration: configuration)
        }
    }

    func fetchSnapshot(for request: CodexRateLimitRequest) async -> CodexRateLimitSnapshot? {
        if let remoteSnapshot = await fetchRemoteSnapshot(for: request) {
            return remoteSnapshot
        }

        guard request.isCurrentAccount, let linkedLocation = request.linkedLocation else {
            return nil
        }

        let fallbackObservation = await sessionReader.readLatestObservation(
            in: linkedLocation.folderURL
        )

        guard let fallbackObservation else {
            return nil
        }

        return CodexRateLimitSnapshot(
            identityKey: request.identityKey,
            observedAt: fallbackObservation.observedAt,
            fetchedAt: .now,
            source: .sessionLogFallback,
            sevenDayRemainingPercent: fallbackObservation.sevenDayRemainingPercent,
            fiveHourRemainingPercent: fallbackObservation.fiveHourRemainingPercent,
            sevenDayResetsAt: fallbackObservation.sevenDayResetsAt,
            fiveHourResetsAt: fallbackObservation.fiveHourResetsAt
        ).applyingResetBoundaries()
    }

    private func fetchRemoteSnapshot(for request: CodexRateLimitRequest) async -> CodexRateLimitSnapshot? {
        guard
            let authFileContents = request.authFileContents,
            let credentials = try? CodexAuthFile.parseRateLimitCredentials(contents: authFileContents),
            credentials.identityKey == request.identityKey,
            credentials.authMode != .apiKey,
            let accessToken = credentials.accessToken,
            !accessToken.isEmpty
        else {
            return nil
        }

        await requestLimiter.acquire()

        var urlRequest = URLRequest(url: Self.usageURL)
        urlRequest.httpMethod = "GET"
        urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        if let accountID = credentials.accountID, !accountID.isEmpty {
            urlRequest.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        do {
            let (data, response) = try await urlSession.data(for: urlRequest)
            guard
                let httpResponse = response as? HTTPURLResponse,
                200..<300 ~= httpResponse.statusCode,
                let remoteResponse = try? JSONDecoder().decode(CodexUsageAPIResponse.self, from: data)
            else {
                return nil
            }

            return makeSnapshot(from: remoteResponse, identityKey: request.identityKey)
        } catch {
            return nil
        }
    }

    private func makeSnapshot(
        from response: CodexUsageAPIResponse,
        identityKey: String
    ) -> CodexRateLimitSnapshot? {
        let buckets = response.preferredBuckets
        guard !buckets.isEmpty else {
            return nil
        }

        let selectedBucket = buckets.first(where: { $0.matchesCodexBucket })
            ?? buckets.first(where: { $0.limitName?.localizedCaseInsensitiveContains("codex") == true })
            ?? buckets.first

        guard let selectedBucket else {
            return nil
        }

        let windows = selectedBucket.normalizedWindows(referenceDate: .now)

        let fiveHourWindow = selectDisplayWindow(
            from: windows,
            preferredMinutes: 300,
            acceptedRange: 240...360
        )
        let sevenDayWindow = selectDisplayWindow(
            from: windows,
            preferredMinutes: 10_080,
            acceptedRange: 9_900...10_200
        )

        guard fiveHourWindow != nil || sevenDayWindow != nil else {
            return nil
        }

        return CodexRateLimitSnapshot(
            identityKey: identityKey,
            observedAt: .now,
            fetchedAt: .now,
            source: .remoteUsageAPI,
            sevenDayRemainingPercent: sevenDayWindow?.remainingPercent,
            fiveHourRemainingPercent: fiveHourWindow?.remainingPercent,
            sevenDayResetsAt: sevenDayWindow?.resetsAt,
            fiveHourResetsAt: fiveHourWindow?.resetsAt
        ).applyingResetBoundaries()
    }

    private func selectDisplayWindow(
        from windows: [NormalizedUsageWindow],
        preferredMinutes: Int,
        acceptedRange: ClosedRange<Int>
    ) -> NormalizedUsageWindow? {
        windows
            .filter { acceptedRange.contains($0.windowMinutes) }
            .min { lhs, rhs in
                abs(lhs.windowMinutes - preferredMinutes) < abs(rhs.windowMinutes - preferredMinutes)
            }
    }
}

private nonisolated struct NormalizedUsageWindow {
    let windowMinutes: Int
    let remainingPercent: Int
    let resetsAt: Date?
}

private nonisolated struct CodexUsageAPIResponse: Decodable {
    let rateLimit: CodexUsageBucket?
    let rateLimits: CodexUsageBucket?
    let rateLimitsByLimitId: [String: CodexUsageBucket]?
    let primaryWindow: CodexUsageWindow?
    let secondaryWindow: CodexUsageWindow?

    enum CodingKeys: String, CodingKey {
        case rateLimit = "rate_limit"
        case rateLimits
        case rateLimitsByLimitId = "rate_limits_by_limit_id"
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }

    var preferredBuckets: [CodexUsageBucket] {
        var buckets = rateLimitsByLimitId?.values.map { $0 } ?? []

        if let rateLimits {
            buckets.append(rateLimits)
        }

        if let rateLimit {
            buckets.append(rateLimit)
        }

        if primaryWindow != nil || secondaryWindow != nil {
            buckets.append(
                CodexUsageBucket(
                    limitId: "codex",
                    limitName: "codex",
                    primaryWindow: primaryWindow,
                    secondaryWindow: secondaryWindow,
                    primary: nil,
                    secondary: nil
                )
            )
        }

        return buckets
    }
}

private nonisolated struct CodexUsageBucket: Decodable {
    let limitId: String?
    let limitName: String?
    let primaryWindow: CodexUsageWindow?
    let secondaryWindow: CodexUsageWindow?
    let primary: CodexUsageWindow?
    let secondary: CodexUsageWindow?

    enum CodingKeys: String, CodingKey {
        case limitId = "limit_id"
        case limitName = "limit_name"
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
        case primary
        case secondary
    }

    var matchesCodexBucket: Bool {
        if limitId == "codex" {
            return true
        }

        return limitName?.localizedCaseInsensitiveCompare("codex") == .orderedSame
    }

    func normalizedWindows(referenceDate: Date) -> [NormalizedUsageWindow] {
        [primaryWindow, secondaryWindow, primary, secondary].compactMap { window in
            guard
                let window,
                let windowMinutes = window.normalizedWindowMinutes,
                let remainingPercent = window.remainingPercent(relativeTo: referenceDate)
            else {
                return nil
            }

            return NormalizedUsageWindow(
                windowMinutes: windowMinutes,
                remainingPercent: remainingPercent,
                resetsAt: window.resolvedResetDate(relativeTo: referenceDate)
            )
        }
    }
}

private nonisolated struct CodexUsageWindow: Decodable {
    let usedPercent: Double?
    let windowDurationMins: Int?
    let limitWindowSeconds: Int?
    let resetsAt: Int?
    let resetAt: Int?
    let resetAfterSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case usedPercent
        case usedPercentSnake = "used_percent"
        case windowDurationMins
        case windowDurationMinsSnake = "window_duration_mins"
        case limitWindowSeconds = "limit_window_seconds"
        case resetsAt
        case resetsAtSnake = "resets_at"
        case resetAt = "reset_at"
        case resetAfterSeconds = "reset_after_seconds"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // The public usage endpoint has already shipped both snake_case and
        // camelCase variants in community tooling and samples. Accept both so a
        // small schema drift does not silently zero out the rate-limit display.
        usedPercent = try container.decodeIfPresent(Double.self, forKey: .usedPercent)
            ?? container.decodeIfPresent(Double.self, forKey: .usedPercentSnake)
        windowDurationMins = try container.decodeIfPresent(Int.self, forKey: .windowDurationMins)
            ?? container.decodeIfPresent(Int.self, forKey: .windowDurationMinsSnake)
        limitWindowSeconds = try container.decodeIfPresent(Int.self, forKey: .limitWindowSeconds)
        resetsAt = try container.decodeIfPresent(Int.self, forKey: .resetsAt)
            ?? container.decodeIfPresent(Int.self, forKey: .resetsAtSnake)
        resetAt = try container.decodeIfPresent(Int.self, forKey: .resetAt)
        resetAfterSeconds = try container.decodeIfPresent(Int.self, forKey: .resetAfterSeconds)
    }

    var normalizedWindowMinutes: Int? {
        if let windowDurationMins {
            return windowDurationMins
        }

        if let limitWindowSeconds {
            return Int((Double(limitWindowSeconds) / 60).rounded())
        }

        return nil
    }

    func resolvedResetDate(relativeTo referenceDate: Date) -> Date? {
        if let resetsAt {
            return Date(timeIntervalSince1970: TimeInterval(resetsAt))
        }

        if let resetAt {
            return Date(timeIntervalSince1970: TimeInterval(resetAt))
        }

        if let resetAfterSeconds {
            return referenceDate.addingTimeInterval(TimeInterval(resetAfterSeconds))
        }

        return nil
    }

    func remainingPercent(relativeTo referenceDate: Date) -> Int? {
        guard let usedPercent, usedPercent.isFinite else {
            return nil
        }

        if let resetDate = resolvedResetDate(relativeTo: referenceDate), referenceDate >= resetDate {
            return 100
        }

        let clampedUsed = min(max(Int(usedPercent.rounded()), 0), 100)
        return 100 - clampedUsed
    }
}
