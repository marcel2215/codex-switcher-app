//
//  RateLimitProvider.swift
//  Codex Switcher
//
//  Created by Marcel Kwiatkowski on 2026-04-11.
//

import Foundation

nonisolated struct CodexRateLimitRequest: Sendable {
    let identityKey: String
    let credentials: CodexRateLimitCredentials?
    let linkedLocation: AuthLinkedLocation?
    let isCurrentAccount: Bool
}

nonisolated enum CodexRateLimitFetchFailure: Sendable, Equatable {
    case missingCredentials
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case httpStatus(Int)
    case invalidResponse
    case invalidPayload
    case network(URLError.Code)
    case cancelled
}

nonisolated struct CodexRateLimitFetchResult: Sendable, Equatable {
    let snapshot: CodexRateLimitSnapshot?
    let remoteFailure: CodexRateLimitFetchFailure?

    init(snapshot: CodexRateLimitSnapshot? = nil, remoteFailure: CodexRateLimitFetchFailure? = nil) {
        self.snapshot = snapshot
        self.remoteFailure = remoteFailure
    }
}

protocol CodexRateLimitProviding: Sendable {
    func fetchSnapshot(for request: CodexRateLimitRequest) async -> CodexRateLimitFetchResult
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
#if os(watchOS)
            // watchOS requests may go through the paired phone, Wi-Fi, or the
            // watch's own network path, so give the foreground fetch a slightly
            // larger budget before treating it as transiently unavailable.
            configuration.timeoutIntervalForRequest = 15
            configuration.timeoutIntervalForResource = 30
#else
            configuration.timeoutIntervalForRequest = 8
            configuration.timeoutIntervalForResource = 12
#endif
            configuration.httpAdditionalHeaders = [
                "Accept": "application/json",
                "User-Agent": "Codex Switcher",
            ]
            self.urlSession = URLSession(configuration: configuration)
        }
    }

    func fetchSnapshot(for request: CodexRateLimitRequest) async -> CodexRateLimitFetchResult {
        let remoteResult = await fetchRemoteSnapshot(for: request)
        if remoteResult.snapshot != nil || remoteResult.remoteFailure == .cancelled {
            return remoteResult
        }

        guard request.isCurrentAccount, let linkedLocation = request.linkedLocation else {
            return remoteResult
        }

        let fallbackObservation = await sessionReader.readLatestObservation(
            in: linkedLocation.folderURL
        )

        guard let fallbackObservation else {
            return remoteResult
        }

        let snapshot = CodexRateLimitSnapshot(
            identityKey: request.identityKey,
            observedAt: fallbackObservation.observedAt,
            fetchedAt: .now,
            source: .sessionLogFallback,
            sevenDayRemainingPercent: fallbackObservation.sevenDayRemainingPercent,
            fiveHourRemainingPercent: fallbackObservation.fiveHourRemainingPercent,
            sevenDayResetsAt: fallbackObservation.sevenDayResetsAt,
            fiveHourResetsAt: fallbackObservation.fiveHourResetsAt
        ).applyingResetBoundaries()
        return CodexRateLimitFetchResult(
            snapshot: snapshot,
            remoteFailure: remoteResult.remoteFailure
        )
    }

    private func fetchRemoteSnapshot(for request: CodexRateLimitRequest) async -> CodexRateLimitFetchResult {
        guard
            let credentials = request.credentials,
            credentials.identityKey == request.identityKey,
            credentials.authMode != .apiKey,
            let accessToken = credentials.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines),
            !accessToken.isEmpty
        else {
            return CodexRateLimitFetchResult(remoteFailure: .missingCredentials)
        }

        var urlRequest = URLRequest(url: Self.usageURL)
        urlRequest.httpMethod = "GET"
        urlRequest.cachePolicy = .reloadIgnoringLocalCacheData
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        if let accountID = credentials.accountID?.trimmingCharacters(in: .whitespacesAndNewlines), !accountID.isEmpty {
            urlRequest.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        do {
            try await requestLimiter.acquire()
            let (data, response) = try await urlSession.data(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                return CodexRateLimitFetchResult(remoteFailure: .invalidResponse)
            }

            switch httpResponse.statusCode {
            case 200..<300:
                do {
                    let decoded = try JSONDecoder().decode(CodexUsageAPIResponse.self, from: data)
                    guard let snapshot = makeSnapshot(from: decoded, identityKey: request.identityKey) else {
                        return CodexRateLimitFetchResult(remoteFailure: .invalidPayload)
                    }

                    return CodexRateLimitFetchResult(snapshot: snapshot)
                } catch {
                    return CodexRateLimitFetchResult(remoteFailure: .invalidPayload)
                }

            case 401, 403:
                return CodexRateLimitFetchResult(remoteFailure: .unauthorized)

            case 429:
                return CodexRateLimitFetchResult(
                    remoteFailure: .rateLimited(retryAfter: retryAfterSeconds(from: httpResponse))
                )

            default:
                return CodexRateLimitFetchResult(remoteFailure: .httpStatus(httpResponse.statusCode))
            }
        } catch is CancellationError {
            return CodexRateLimitFetchResult(remoteFailure: .cancelled)
        } catch let error as URLError where error.code == .cancelled {
            return CodexRateLimitFetchResult(remoteFailure: .cancelled)
        } catch let error as URLError {
            return CodexRateLimitFetchResult(remoteFailure: .network(error.code))
        } catch {
            return CodexRateLimitFetchResult(remoteFailure: .invalidResponse)
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

    private func retryAfterSeconds(from response: HTTPURLResponse) -> TimeInterval? {
        guard let header = response.value(forHTTPHeaderField: "Retry-After")?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !header.isEmpty else {
            return nil
        }

        if let seconds = TimeInterval(header), seconds.isFinite, seconds >= 0 {
            return seconds
        }

        for format in [
            "EEE',' dd MMM yyyy HH':'mm':'ss zzz",
            "EEEE',' dd-MMM-yy HH':'mm':'ss zzz",
            "EEE MMM d HH':'mm':'ss yyyy",
        ] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format

            if let date = formatter.date(from: header) {
                return max(date.timeIntervalSinceNow, 0)
            }
        }

        return nil
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
    let limitWindowSeconds: Int?
    let limitWindowMinutes: Int?
    let resetAt: Double?
    let resetsAt: Double?
    let resetSeconds: Double?
    let remainingPercentValue: Double?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case limitWindowSeconds = "limit_window_seconds"
        case limitWindowMinutes = "limit_window_minutes"
        case resetAt = "reset_at"
        case resetsAt = "resets_at"
        case resetSeconds = "reset_seconds"
        case remainingPercentValue = "remaining_percent"
    }

    var normalizedWindowMinutes: Int? {
        if let limitWindowMinutes {
            return limitWindowMinutes
        }

        if let limitWindowSeconds {
            return Int((Double(limitWindowSeconds) / 60).rounded())
        }

        return nil
    }

    func remainingPercent(relativeTo referenceDate: Date) -> Int? {
        if let remainingPercentValue, remainingPercentValue.isFinite {
            return min(max(Int(remainingPercentValue.rounded()), 0), 100)
        }

        guard let usedPercent, usedPercent.isFinite else {
            return nil
        }

        let clampedUsedPercent = min(max(Int(usedPercent.rounded()), 0), 100)
        if let resetDate = resolvedResetDate(relativeTo: referenceDate), referenceDate >= resetDate {
            return 100
        }

        return 100 - clampedUsedPercent
    }

    func resolvedResetDate(relativeTo referenceDate: Date) -> Date? {
        if let resetAt, resetAt.isFinite {
            return Date(timeIntervalSince1970: resetAt)
        }

        if let resetsAt, resetsAt.isFinite {
            return Date(timeIntervalSince1970: resetsAt)
        }

        if let resetSeconds, resetSeconds.isFinite {
            return referenceDate.addingTimeInterval(resetSeconds)
        }

        return nil
    }
}
