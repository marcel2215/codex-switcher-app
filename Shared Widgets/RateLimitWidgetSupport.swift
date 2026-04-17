//
//  RateLimitWidgetSupport.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-12.
//

import AppIntents
import Foundation
import SwiftUI
import WidgetKit

struct WidgetRateLimitMetric: Sendable {
    let remainingPercent: Int?
    let resetsAt: Date?
    let status: RateLimitMetricDataStatus

    var clampedPercent: Int? {
        AccountDisplayFormatter.clampedPercentValue(remainingPercent)
    }

    var fraction: Double {
        Double(clampedPercent ?? 0) / 100
    }

    var percentText: String {
        AccountDisplayFormatter.compactPercentDescription(remainingPercent)
    }

    func tint(
        colorScheme: ColorScheme,
        contrast: ColorSchemeContrast
    ) -> Color {
        switch status {
        case .cached, .missing:
            return .gray
        case .exact:
            let components = AccountDisplayFormatter.adaptiveUsageColorComponents(
                forRemainingPercent: clampedPercent ?? 0,
                colorScheme: colorScheme,
                contrast: contrast
            )

            return Color(
                .sRGB,
                red: components.red,
                green: components.green,
                blue: components.blue,
                opacity: 1
            )
        }
    }
}

struct WidgetRateLimitAccount: Identifiable, Sendable {
    let id: String
    let name: String
    let iconSystemName: String
    let isMissingAccount: Bool
    let fiveHourMetric: WidgetRateLimitMetric
    let sevenDayMetric: WidgetRateLimitMetric

    var displayName: String {
        isMissingAccount ? "Missing Account" : name
    }

    func metric(for window: RateLimitWindow) -> WidgetRateLimitMetric {
        switch window {
        case .fiveHour:
            fiveHourMetric
        case .sevenDay:
            sevenDayMetric
        }
    }

    static func live(from record: SharedCodexAccountRecord) -> Self {
        Self(
            id: record.id,
            name: record.name,
            iconSystemName: record.iconSystemName,
            isMissingAccount: false,
            fiveHourMetric: .init(
                remainingPercent: record.fiveHourLimitUsedPercent,
                resetsAt: record.fiveHourResetsAt,
                status: record.fiveHourDataStatus
            ),
            sevenDayMetric: .init(
                remainingPercent: record.sevenDayLimitUsedPercent,
                resetsAt: record.sevenDayResetsAt,
                status: record.sevenDayDataStatus
            )
        )
    }

    static func missing(id: String) -> Self {
        Self(
            id: id,
            name: "Missing Account",
            iconSystemName: "questionmark.circle.fill",
            isMissingAccount: true,
            fiveHourMetric: .init(remainingPercent: nil, resetsAt: nil, status: .missing),
            sevenDayMetric: .init(remainingPercent: nil, resetsAt: nil, status: .missing)
        )
    }

    static let placeholder = Self(
        id: "preview-account",
        name: "Personal",
        iconSystemName: "key.fill",
        isMissingAccount: false,
        fiveHourMetric: .init(remainingPercent: 72, resetsAt: .now.addingTimeInterval(2 * 60 * 60), status: .exact),
        sevenDayMetric: .init(remainingPercent: 83, resetsAt: .now.addingTimeInterval(2 * 24 * 60 * 60), status: .exact)
    )

    static let cachedPlaceholder = Self(
        id: "preview-cached",
        name: "Cached Account",
        iconSystemName: "house.fill",
        isMissingAccount: false,
        fiveHourMetric: .init(remainingPercent: 61, resetsAt: .now.addingTimeInterval(90 * 60), status: .cached),
        sevenDayMetric: .init(remainingPercent: 79, resetsAt: .now.addingTimeInterval(3 * 24 * 60 * 60), status: .cached)
    )
}

struct RateLimitAccessoryEntry: TimelineEntry {
    let date: Date
    let account: WidgetRateLimitAccount?
    let window: RateLimitWindow
}

enum WidgetRateLimitResolver {
    static func loadState() -> SharedCodexState {
        (try? CodexSharedStateStore().load()) ?? .empty
    }

#if !os(watchOS)
    static func synchronizeResetNotifications(
        with state: SharedCodexState,
        isPreview: Bool
    ) async {
        guard !isPreview else {
            return
        }

        await RateLimitResetNotificationScheduler.shared.synchronize(with: state)
    }
#endif

#if !os(watchOS)
    static func overviewAccounts(
        for configuration: RateLimitOverviewConfigurationIntent,
        family: WidgetFamily,
        state: SharedCodexState
    ) -> [WidgetRateLimitAccount] {
        let requestedIDs = [
            configuration.account1?.id,
            configuration.account2?.id,
            configuration.account3?.id,
            configuration.account4?.id,
            configuration.account5?.id,
        ]

        return overviewAccounts(
            requestedIDs: requestedIDs,
            family: family,
            state: state
        )
    }

    static func overviewAccounts(
        requestedIDs: [String?],
        family: WidgetFamily,
        state: SharedCodexState
    ) -> [WidgetRateLimitAccount] {
        let capacity = overviewCapacity(for: family)
        guard capacity > 0 else {
            return []
        }

        let slots = Array(requestedIDs.prefix(capacity))
        let sortedRecords = state.accounts.sorted(by: accountRecordComparator)

        var reservedExplicitIDs = Set<String>()
        for requestedID in slots.compactMap(normalizedIdentityKey(_:)) {
            reservedExplicitIDs.insert(requestedID)
        }

        let fallbackRecords = sortedRecords.filter { !reservedExplicitIDs.contains($0.id) }
        var fallbackIndex = 0

        var resolvedAccounts: [WidgetRateLimitAccount] = []
        var usedIDs = Set<String>()

        for requestedSlot in slots {
            func appendNextFallbackAccount() {
                while fallbackIndex < fallbackRecords.count {
                    let record = fallbackRecords[fallbackIndex]
                    fallbackIndex += 1

                    guard usedIDs.insert(record.id).inserted else {
                        continue
                    }

                    resolvedAccounts.append(.live(from: record))
                    break
                }
            }

            guard let requestedID = normalizedIdentityKey(requestedSlot) else {
                appendNextFallbackAccount()
                continue
            }

            guard usedIDs.insert(requestedID).inserted else {
                appendNextFallbackAccount()
                continue
            }

            if let record = state.account(withIdentityKey: requestedID) {
                resolvedAccounts.append(.live(from: record))
            } else {
                resolvedAccounts.append(.missing(id: requestedID))
            }
        }

        return Array(resolvedAccounts.prefix(capacity))
    }
#endif

    static func accessoryAccount(
        for configuration: RateLimitAccessoryConfigurationIntent,
        state: SharedCodexState
    ) -> WidgetRateLimitAccount? {
        if let requestedID = normalizedIdentityKey(configuration.account?.id) {
            if let record = state.account(withIdentityKey: requestedID) {
                return .live(from: record)
            }

            return .missing(id: requestedID)
        }

        guard let firstAccount = state.accounts.sorted(by: accountRecordComparator).first else {
            return nil
        }

        return .live(from: firstAccount)
    }

    static func nextReset(in accounts: [WidgetRateLimitAccount]) -> Date? {
        accounts
            .flatMap { [$0.fiveHourMetric, $0.sevenDayMetric] }
            .compactMap(nextReset(for:))
            .min()
    }

    static func nextReset(
        for account: WidgetRateLimitAccount?,
        window: RateLimitWindow
    ) -> Date? {
        guard let account else {
            return nil
        }

        return nextReset(for: account.metric(for: window))
    }

    private static func nextReset(for metric: WidgetRateLimitMetric) -> Date? {
        guard metric.status == .exact, let resetsAt = metric.resetsAt else {
            return nil
        }

        return resetsAt
    }

    #if !os(watchOS)
    private static func overviewCapacity(for family: WidgetFamily) -> Int {
        switch family {
        case .systemSmall:
            1
        case .systemMedium:
            2
        case .systemLarge:
            5
        default:
            1
        }
    }
    #endif

    private static func normalizedIdentityKey(_ identityKey: String?) -> String? {
        guard let identityKey = identityKey?.trimmingCharacters(in: .whitespacesAndNewlines), !identityKey.isEmpty else {
            return nil
        }

        guard identityKey != WidgetCodexAccountEntity.automaticID else {
            return nil
        }

        return identityKey
    }

    static func accountRecordComparator(
        lhs: SharedCodexAccountRecord,
        rhs: SharedCodexAccountRecord
    ) -> Bool {
        AccountsPresentationLogic.sharedAccountRecordComparator(lhs: lhs, rhs: rhs)
    }
}

enum WidgetTimelineScheduler {
    private static let minimumReloadInterval: TimeInterval = 5 * 60
    private static let fallbackReloadInterval: TimeInterval = 30 * 60

    static func reloadDate(after now: Date, nextReset: Date?) -> Date {
        guard let nextReset else {
            return now.addingTimeInterval(fallbackReloadInterval)
        }

        return max(
            nextReset.addingTimeInterval(60),
            now.addingTimeInterval(minimumReloadInterval)
        )
    }
}

#if !os(watchOS)
struct RateLimitOverviewEntry: TimelineEntry {
    let date: Date
    let accounts: [WidgetRateLimitAccount]
}

struct RateLimitOverviewProvider: AppIntentTimelineProvider {
    typealias Intent = RateLimitOverviewConfigurationIntent
    typealias Entry = RateLimitOverviewEntry

    func recommendations() -> [AppIntentRecommendation<RateLimitOverviewConfigurationIntent>] {
        let state = WidgetRateLimitResolver.loadState()
        let suggestedAccounts = state.accounts
            .sorted(by: WidgetRateLimitResolver.accountRecordComparator)
            .prefix(5)
            .map(WidgetCodexAccountEntity.live(from:))

        let intent = RateLimitOverviewConfigurationIntent()
        intent.account1 = suggestedAccounts[safe: 0]
        intent.account2 = suggestedAccounts[safe: 1]
        intent.account3 = suggestedAccounts[safe: 2]
        intent.account4 = suggestedAccounts[safe: 3]
        intent.account5 = suggestedAccounts[safe: 4]

        return [
            AppIntentRecommendation(intent: intent, description: "Rate Limits")
        ]
    }

    func placeholder(in context: Context) -> RateLimitOverviewEntry {
        RateLimitOverviewEntry(
            date: .now,
            accounts: WidgetRateLimitResolver.overviewAccounts(
                requestedIDs: [],
                family: context.family,
                state: previewState
            )
        )
    }

    func snapshot(
        for configuration: RateLimitOverviewConfigurationIntent,
        in context: Context
    ) async -> RateLimitOverviewEntry {
        let state = WidgetRateLimitResolver.loadState()
        await WidgetRateLimitResolver.synchronizeResetNotifications(with: state, isPreview: context.isPreview)
        return RateLimitOverviewEntry(
            date: .now,
            accounts: WidgetRateLimitResolver.overviewAccounts(
                for: configuration,
                family: context.family,
                state: state
            )
        )
    }

    func timeline(
        for configuration: RateLimitOverviewConfigurationIntent,
        in context: Context
    ) async -> Timeline<RateLimitOverviewEntry> {
        let now = Date()
        let state = WidgetRateLimitResolver.loadState()
        await WidgetRateLimitResolver.synchronizeResetNotifications(with: state, isPreview: context.isPreview)
        let accounts = WidgetRateLimitResolver.overviewAccounts(
            for: configuration,
            family: context.family,
            state: state
        )
        let entry = RateLimitOverviewEntry(date: now, accounts: accounts)

        return Timeline(
            entries: [entry],
            policy: .after(
                WidgetTimelineScheduler.reloadDate(
                    after: now,
                    nextReset: WidgetRateLimitResolver.nextReset(in: accounts)
                )
            )
        )
    }

    private var previewState: SharedCodexState {
        SharedCodexState(
            schemaVersion: SharedCodexState.currentSchemaVersion,
            authState: .ready,
            linkedFolderPath: nil,
            currentAccountID: WidgetRateLimitAccount.placeholder.id,
            selectedAccountID: nil,
            selectedAccountIsLive: false,
            accounts: [
                SharedCodexAccountRecord(
                    id: WidgetRateLimitAccount.placeholder.id,
                    name: WidgetRateLimitAccount.placeholder.name,
                    iconSystemName: WidgetRateLimitAccount.placeholder.iconSystemName,
                    emailHint: nil,
                    accountIdentifier: nil,
                    authModeRaw: "chatgpt",
                    lastLoginAt: .now,
                    sevenDayLimitUsedPercent: WidgetRateLimitAccount.placeholder.sevenDayMetric.remainingPercent,
                    fiveHourLimitUsedPercent: WidgetRateLimitAccount.placeholder.fiveHourMetric.remainingPercent,
                    sevenDayResetsAt: WidgetRateLimitAccount.placeholder.sevenDayMetric.resetsAt,
                    fiveHourResetsAt: WidgetRateLimitAccount.placeholder.fiveHourMetric.resetsAt,
                    sevenDayDataStatusRaw: WidgetRateLimitAccount.placeholder.sevenDayMetric.status.rawValue,
                    fiveHourDataStatusRaw: WidgetRateLimitAccount.placeholder.fiveHourMetric.status.rawValue,
                    rateLimitsObservedAt: .now,
                    sortOrder: 0,
                    hasLocalSnapshot: true
                ),
                SharedCodexAccountRecord(
                    id: WidgetRateLimitAccount.cachedPlaceholder.id,
                    name: WidgetRateLimitAccount.cachedPlaceholder.name,
                    iconSystemName: WidgetRateLimitAccount.cachedPlaceholder.iconSystemName,
                    emailHint: nil,
                    accountIdentifier: nil,
                    authModeRaw: "chatgpt",
                    lastLoginAt: .now,
                    sevenDayLimitUsedPercent: WidgetRateLimitAccount.cachedPlaceholder.sevenDayMetric.remainingPercent,
                    fiveHourLimitUsedPercent: WidgetRateLimitAccount.cachedPlaceholder.fiveHourMetric.remainingPercent,
                    sevenDayResetsAt: WidgetRateLimitAccount.cachedPlaceholder.sevenDayMetric.resetsAt,
                    fiveHourResetsAt: WidgetRateLimitAccount.cachedPlaceholder.fiveHourMetric.resetsAt,
                    sevenDayDataStatusRaw: WidgetRateLimitAccount.cachedPlaceholder.sevenDayMetric.status.rawValue,
                    fiveHourDataStatusRaw: WidgetRateLimitAccount.cachedPlaceholder.fiveHourMetric.status.rawValue,
                    rateLimitsObservedAt: .now,
                    sortOrder: 1,
                    hasLocalSnapshot: true
                ),
                SharedCodexAccountRecord(
                    id: "preview-account-3",
                    name: "Family",
                    iconSystemName: "house.fill",
                    emailHint: nil,
                    accountIdentifier: nil,
                    authModeRaw: "chatgpt",
                    lastLoginAt: .now,
                    sevenDayLimitUsedPercent: 84,
                    fiveHourLimitUsedPercent: 100,
                    sevenDayResetsAt: .now.addingTimeInterval(4 * 24 * 60 * 60),
                    fiveHourResetsAt: .now.addingTimeInterval(5 * 60 * 60),
                    sevenDayDataStatusRaw: RateLimitMetricDataStatus.exact.rawValue,
                    fiveHourDataStatusRaw: RateLimitMetricDataStatus.exact.rawValue,
                    rateLimitsObservedAt: .now,
                    sortOrder: 2,
                    hasLocalSnapshot: true
                ),
                SharedCodexAccountRecord(
                    id: "preview-account-4",
                    name: "School",
                    iconSystemName: "graduationcap.fill",
                    emailHint: nil,
                    accountIdentifier: nil,
                    authModeRaw: "chatgpt",
                    lastLoginAt: .now,
                    sevenDayLimitUsedPercent: 75,
                    fiveHourLimitUsedPercent: 100,
                    sevenDayResetsAt: .now.addingTimeInterval(4 * 24 * 60 * 60),
                    fiveHourResetsAt: .now.addingTimeInterval(5 * 60 * 60),
                    sevenDayDataStatusRaw: RateLimitMetricDataStatus.exact.rawValue,
                    fiveHourDataStatusRaw: RateLimitMetricDataStatus.exact.rawValue,
                    rateLimitsObservedAt: .now,
                    sortOrder: 3,
                    hasLocalSnapshot: true
                ),
                SharedCodexAccountRecord(
                    id: "preview-account-5",
                    name: "Maja",
                    iconSystemName: "heart.fill",
                    emailHint: nil,
                    accountIdentifier: nil,
                    authModeRaw: "chatgpt",
                    lastLoginAt: .now,
                    sevenDayLimitUsedPercent: 100,
                    fiveHourLimitUsedPercent: 100,
                    sevenDayResetsAt: .now.addingTimeInterval(4 * 24 * 60 * 60),
                    fiveHourResetsAt: .now.addingTimeInterval(5 * 60 * 60),
                    sevenDayDataStatusRaw: RateLimitMetricDataStatus.exact.rawValue,
                    fiveHourDataStatusRaw: RateLimitMetricDataStatus.exact.rawValue,
                    rateLimitsObservedAt: .now,
                    sortOrder: 4,
                    hasLocalSnapshot: true
                ),
            ],
            updatedAt: .now
        )
    }
}
#endif

struct RateLimitAccessoryProvider: AppIntentTimelineProvider {
    typealias Intent = RateLimitAccessoryConfigurationIntent
    typealias Entry = RateLimitAccessoryEntry

    func recommendations() -> [AppIntentRecommendation<RateLimitAccessoryConfigurationIntent>] {
        // watchOS complications don't get the dedicated parameter editor that
        // widgets have on iOS and macOS. The watch gallery is driven by the
        // preconfigured recommendations we return here, so expose Automatic plus
        // every account in app order for both windows.
        let entities = [WidgetCodexAccountEntity.automatic]
            + WidgetRateLimitResolver.loadState().accounts
                .sorted(by: WidgetRateLimitResolver.accountRecordComparator)
                .map(WidgetCodexAccountEntity.live(from:))

        return entities.flatMap { entity in
            let accountName = entity.isAutomatic ? "Automatic" : entity.name
            let fiveHourDescription = accountName + " • 5h"
            let sevenDayDescription = accountName + " • 7d"

            let fiveHourIntent: RateLimitAccessoryConfigurationIntent = {
                let intent = RateLimitAccessoryConfigurationIntent()
                intent.account = entity
                intent.window = .fiveHour
                return intent
            }()

            let sevenDayIntent: RateLimitAccessoryConfigurationIntent = {
                let intent = RateLimitAccessoryConfigurationIntent()
                intent.account = entity
                intent.window = .sevenDay
                return intent
            }()

            return [
                AppIntentRecommendation(
                    intent: fiveHourIntent,
                    description: fiveHourDescription
                ),
                AppIntentRecommendation(
                    intent: sevenDayIntent,
                    description: sevenDayDescription
                ),
            ]
        }
    }

    func placeholder(in context: Context) -> RateLimitAccessoryEntry {
        RateLimitAccessoryEntry(
            date: .now,
            account: WidgetRateLimitAccount.placeholder,
            window: .fiveHour
        )
    }

    func snapshot(
        for configuration: RateLimitAccessoryConfigurationIntent,
        in context: Context
    ) async -> RateLimitAccessoryEntry {
        let state = WidgetRateLimitResolver.loadState()
#if !os(watchOS)
        await WidgetRateLimitResolver.synchronizeResetNotifications(with: state, isPreview: context.isPreview)
#endif
        return RateLimitAccessoryEntry(
            date: .now,
            account: WidgetRateLimitResolver.accessoryAccount(for: configuration, state: state),
            window: configuration.window
        )
    }

    func timeline(
        for configuration: RateLimitAccessoryConfigurationIntent,
        in context: Context
    ) async -> Timeline<RateLimitAccessoryEntry> {
        let now = Date()
        let state = WidgetRateLimitResolver.loadState()
#if !os(watchOS)
        await WidgetRateLimitResolver.synchronizeResetNotifications(with: state, isPreview: context.isPreview)
#endif
        let account = WidgetRateLimitResolver.accessoryAccount(for: configuration, state: state)
        let entry = RateLimitAccessoryEntry(date: now, account: account, window: configuration.window)

        return Timeline(
            entries: [entry],
            policy: .after(
                WidgetTimelineScheduler.reloadDate(
                    after: now,
                    nextReset: WidgetRateLimitResolver.nextReset(for: account, window: configuration.window)
                )
            )
        )
    }
}

#if !os(watchOS)
private enum RateLimitOverviewMetricLayout {
    static let percentLabelMinimumWidth: CGFloat = 42
}

struct RateLimitOverviewWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: RateLimitOverviewEntry

    var body: some View {
        if entry.accounts.isEmpty {
            RateLimitOverviewEmptyState()
        } else {
            VStack(alignment: .leading, spacing: verticalSpacing) {
                ForEach(Array(entry.accounts.enumerated()), id: \.offset) { index, account in
                    RateLimitOverviewAccountCard(account: account, family: family)
                    if index < entry.accounts.count - 1 {
                        Divider()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var verticalSpacing: CGFloat {
        switch family {
        case .systemSmall:
            6
        case .systemMedium:
            8
        case .systemLarge:
            8
        default:
            6
        }
    }
}
#endif

#if !os(watchOS)
private struct RateLimitOverviewEmptyState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("No Synced Accounts", systemImage: "person.crop.circle.badge.questionmark")
                .font(.headline)

            Text("Open Codex Switcher to let iCloud sync your accounts to this device.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct RateLimitOverviewAccountCard: View {
    private static let iconFont: Font = .system(size: 14, weight: .semibold)
    private static let nameFont: Font = .caption.weight(.semibold)

    let account: WidgetRateLimitAccount
    let family: WidgetFamily

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Image(systemName: account.iconSystemName)
                    .font(Self.iconFont)
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)

                Text(account.displayName)
                    .font(Self.nameFont)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if account.isMissingAccount {
                    Text("?")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if family == .systemSmall {
                VStack(alignment: .leading, spacing: 6) {
                    RateLimitOverviewMetricRow(title: "5h", metric: account.fiveHourMetric)
                    RateLimitOverviewMetricRow(title: "7d", metric: account.sevenDayMetric)
                }
            } else {
                HStack(alignment: .top, spacing: 8) {
                    RateLimitOverviewMetricCell(title: "5h", metric: account.fiveHourMetric)
                    RateLimitOverviewMetricCell(title: "7d", metric: account.sevenDayMetric)
                }
            }
        }
    }
}

private struct RateLimitOverviewMetricRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode

    let title: String
    let metric: WidgetRateLimitMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 4)

                Text(metric.percentText)
                    .font(.caption2.monospacedDigit())
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(
                        minWidth: RateLimitOverviewMetricLayout.percentLabelMinimumWidth,
                        alignment: .trailing
                    )
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.secondary.opacity(0.18))

                    RateLimitMetricBarFill(
                        metric: metric,
                        colorScheme: colorScheme,
                        colorSchemeContrast: colorSchemeContrast,
                        widgetRenderingMode: widgetRenderingMode
                    )
                    .frame(width: proxy.size.width * metric.fraction)
                }
            }
            .frame(height: 6)
        }
    }
}

private struct RateLimitOverviewMetricCell: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode

    let title: String
    let metric: WidgetRateLimitMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 4)

                Text(metric.percentText)
                    .font(.caption2.monospacedDigit())
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(
                        minWidth: RateLimitOverviewMetricLayout.percentLabelMinimumWidth,
                        alignment: .trailing
                    )
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.secondary.opacity(0.18))

                    RateLimitMetricBarFill(
                        metric: metric,
                        colorScheme: colorScheme,
                        colorSchemeContrast: colorSchemeContrast,
                        widgetRenderingMode: widgetRenderingMode
                    )
                    .frame(width: proxy.size.width * metric.fraction)
                }
            }
            .frame(height: 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RateLimitMetricBarFill: View {
    let metric: WidgetRateLimitMetric
    let colorScheme: ColorScheme
    let colorSchemeContrast: ColorSchemeContrast
    let widgetRenderingMode: WidgetRenderingMode

    var body: some View {
        Capsule()
            .fill(fillColor)
            .widgetAccentable()
    }

    private var fillColor: Color {
        if widgetRenderingMode == .accented {
            // iOS Home Screen can collapse semantic widget colors into a single
            // accent tint. Preserve the existing layout, and use alpha to keep
            // cached or missing data visually weaker than exact live values.
            switch metric.status {
            case .exact:
                return .white
            case .cached:
                return .white.opacity(0.6)
            case .missing:
                return .white.opacity(0.35)
            }
        }

        return metric.tint(
            colorScheme: colorScheme,
            contrast: colorSchemeContrast
        )
    }
}
#endif

struct RateLimitCircularAccessoryView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode

    let account: WidgetRateLimitAccount?
    let window: RateLimitWindow

    var body: some View {
        Gauge(value: metric.fraction) {
            EmptyView()
        } currentValueLabel: {
            Image(systemName: iconSystemName)
                .font(.system(size: 16, weight: .semibold))
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(gaugeTint)
#if os(watchOS)
        .widgetLabel {
            Text(window.shortLabel)
        }
#endif
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
    }

    private var metric: WidgetRateLimitMetric {
        account?.metric(for: window) ?? .init(remainingPercent: nil, resetsAt: nil, status: .missing)
    }

    private var gaugeTint: Color {
        if widgetRenderingMode == .vibrant {
            return .white
        }

        return metric.tint(colorScheme: colorScheme, contrast: colorSchemeContrast)
    }

    private var iconSystemName: String {
        account?.iconSystemName ?? "questionmark.circle.fill"
    }

    private var accountName: String {
        account?.displayName ?? "Missing Account"
    }

    private var accessibilityLabel: String {
        "\(accountName) \(window.shortLabel)"
    }

    private var accessibilityValue: String {
        switch metric.status {
        case .exact:
            return "\(metric.percentText) remaining"
        case .cached:
            return "\(metric.percentText) remaining, cached"
        case .missing:
            return "Unavailable"
        }
    }
}

private enum BatteryAccessoryRectangularMetrics {
    static let iconPointSize: CGFloat = 13
    static let valuePointSize: CGFloat = 20
    static let subtitlePointSize: CGFloat = 16.5

    static let topRowSpacing: CGFloat = 6
    static let subtitleTopPadding: CGFloat = 1
    static let barTopPadding: CGFloat = 4

    static let barHeight: CGFloat = 8
}

struct RateLimitRectangularAccessoryView: View {
    let account: WidgetRateLimitAccount?
    let window: RateLimitWindow

    var body: some View {
        // Keep all outer margins system-owned for the Lock Screen accessory and
        // tune only the internal layout so it tracks the built-in Batteries
        // widget more closely.
        VStack(alignment: .leading, spacing: 0) {
            HStack(
                alignment: .center,
                spacing: BatteryAccessoryRectangularMetrics.topRowSpacing
            ) {
                Image(systemName: iconSystemName)
                    .font(.system(
                        size: BatteryAccessoryRectangularMetrics.iconPointSize,
                        weight: .semibold
                    ))
                    .foregroundStyle(.primary)

                Text(metric.percentText)
                    .font(.system(
                        size: BatteryAccessoryRectangularMetrics.valuePointSize,
                        weight: .semibold
                    ))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)
            }

            Text(subtitle)
                .font(.system(
                    size: BatteryAccessoryRectangularMetrics.subtitlePointSize,
                    weight: .regular
                ))
                .lineLimit(1)
                .minimumScaleFactor(0.80)
                .padding(.top, BatteryAccessoryRectangularMetrics.subtitleTopPadding)
                .foregroundStyle(.primary)

            BatteryStyleAccessoryProgressBar(
                fraction: metric.fraction,
                status: metric.status
            )
            .padding(.top, BatteryAccessoryRectangularMetrics.barTopPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityLabel("\(account?.displayName ?? "Missing Account") \(window.shortLabel)")
        .accessibilityValue(accessibilityValue)
    }

    private var metric: WidgetRateLimitMetric {
        account?.metric(for: window) ?? .init(remainingPercent: nil, resetsAt: nil, status: .missing)
    }

    private var iconSystemName: String {
        account?.iconSystemName ?? "questionmark.circle.fill"
    }

    private var subtitle: String {
        switch metric.status {
        case .exact:
            return "\(account?.displayName ?? "Missing Account") • \(window.shortLabel)"
        case .cached:
            return "\(account?.displayName ?? "Missing Account") • \(window.shortLabel) • Cached"
        case .missing:
            return "Missing Account • \(window.shortLabel)"
        }
    }

    private var accessibilityValue: String {
        switch metric.status {
        case .exact:
            return "\(metric.percentText) remaining"
        case .cached:
            return "\(metric.percentText) remaining, cached"
        case .missing:
            return "Unavailable"
        }
    }
}

private struct BatteryStyleAccessoryProgressBar: View {
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode

    let fraction: Double
    let status: RateLimitMetricDataStatus

    var body: some View {
        GeometryReader { proxy in
            let trackWidth = proxy.size.width
            let fillWidth = trackWidth * clampedFraction

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(trackColor)
                    .frame(
                        width: trackWidth,
                        height: BatteryAccessoryRectangularMetrics.barHeight
                    )

                if fillWidth > 0 {
                    Capsule()
                        .fill(fillColor)
                        .frame(
                            width: fillWidth,
                            height: BatteryAccessoryRectangularMetrics.barHeight
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: BatteryAccessoryRectangularMetrics.barHeight)
        .accessibilityHidden(true)
    }

    private var clampedFraction: CGFloat {
        CGFloat(max(0, min(1, fraction)))
    }

    private var trackColor: Color {
        if widgetRenderingMode == .vibrant {
            return Color(white: 0.18)
        }

        return .primary.opacity(0.16)
    }

    private var fillColor: Color {
        if widgetRenderingMode == .vibrant {
            switch status {
            case .exact:
                return .white
            case .cached:
                return Color(white: 0.76)
            case .missing:
                return Color(white: 0.56)
            }
        }

        let baseColor = Color.primary

        switch status {
        case .exact:
            return baseColor
        case .cached:
            return baseColor.opacity(0.72)
        case .missing:
            return baseColor.opacity(0.42)
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else {
            return nil
        }

        return self[index]
    }
}
