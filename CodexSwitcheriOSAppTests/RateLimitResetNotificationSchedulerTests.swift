//
//  RateLimitResetNotificationSchedulerTests.swift
//  Codex Switcher iOS App Tests
//
//  Created by Codex on 2026-04-14.
//

import Foundation
import Testing
import UserNotifications
@testable import CodexSwitcher_iOS_App

struct RateLimitResetNotificationSchedulerTests {
    @Test
    func exactMetricAtFullCapacityDoesNotScheduleResetNotification() async {
        let requests = NotificationRequestRecorder()
        let scheduler = makeScheduler(requests: requests)
        let state = makeSharedState(accounts: [
            makeAccountRecord(
                id: "school",
                name: "School",
                fiveHourLimitUsedPercent: 100,
                fiveHourResetsAt: Date().addingTimeInterval(60 * 30),
                fiveHourDataStatus: .exact
            )
        ])

        await scheduler.synchronize(with: state)

        let recordedRequests = await requests.value()
        #expect(recordedRequests.isEmpty)
    }

    @Test
    func metricSchedulesResetNotificationAfterDroppingBelowFullCapacity() async {
        let requests = NotificationRequestRecorder()
        let scheduler = makeScheduler(requests: requests)
        let resetDate = Date().addingTimeInterval(60 * 30)

        await scheduler.synchronize(with: makeSharedState(accounts: [
            makeAccountRecord(
                id: "school",
                name: "School",
                fiveHourLimitUsedPercent: 100,
                fiveHourResetsAt: resetDate,
                fiveHourDataStatus: .exact
            )
        ]))

        await scheduler.synchronize(with: makeSharedState(accounts: [
            makeAccountRecord(
                id: "school",
                name: "School",
                fiveHourLimitUsedPercent: 82,
                fiveHourResetsAt: resetDate,
                fiveHourDataStatus: .exact
            )
        ]))

        let recordedRequests = await requests.value()
        let firstRequest = recordedRequests.first

        #expect(recordedRequests.count == 1)
        #expect(firstRequest?.identifier.contains("five-hour") == true)
        #expect(firstRequest?.title == "5-Hour Rate Limit Reset")
        #expect(firstRequest?.body == "School is back to 100% for its 5-hour window.")
    }

    @Test
    func inAppResetNotificationSettingsStillGateScheduling() async {
        let requests = NotificationRequestRecorder()
        let removedIdentifiers = RemovedIdentifierRecorder()
        let scheduler = RateLimitResetNotificationScheduler(
            stateStore: .init(),
            notificationPreferencesProvider: {
                .init(fiveHourEnabled: false, sevenDayEnabled: false)
            },
            authorizationStatusProvider: { .authorized },
            addNotificationRequestHandler: { request in
                await requests.append(
                    RecordedNotificationRequest(
                        identifier: request.identifier,
                        title: request.content.title,
                        body: request.content.body
                    )
                )
            },
            pendingNotificationIdentifiersProvider: { ["managed-pending"] },
            deliveredNotificationIdentifiersProvider: { ["managed-delivered"] },
            removeNotificationsHandler: { identifiers in
                removedIdentifiers.append(contentsOf: identifiers)
            }
        )

        await scheduler.synchronize(with: makeSharedState(accounts: [
            makeAccountRecord(
                id: "school",
                name: "School",
                fiveHourLimitUsedPercent: 82,
                fiveHourResetsAt: Date().addingTimeInterval(60 * 30),
                fiveHourDataStatus: .exact
            )
        ]))

        let recordedRequests = await requests.value()
        let removed = removedIdentifiers.value

        #expect(recordedRequests.isEmpty)
        #expect(removed.sorted() == ["managed-delivered", "managed-pending"])
    }
}

private func makeScheduler(
    requests: NotificationRequestRecorder
) -> RateLimitResetNotificationScheduler {
    RateLimitResetNotificationScheduler(
        stateStore: .init(),
        notificationPreferencesProvider: {
            .init(fiveHourEnabled: true, sevenDayEnabled: true)
        },
        authorizationStatusProvider: { .authorized },
        addNotificationRequestHandler: { request in
            await requests.append(
                RecordedNotificationRequest(
                    identifier: request.identifier,
                    title: request.content.title,
                    body: request.content.body
                )
            )
        },
        pendingNotificationIdentifiersProvider: { [] },
        deliveredNotificationIdentifiersProvider: { [] },
        removeNotificationsHandler: { _ in }
    )
}

private func makeSharedState(accounts: [SharedCodexAccountRecord]) -> SharedCodexState {
    SharedCodexState(
        schemaVersion: SharedCodexState.currentSchemaVersion,
        authState: .ready,
        linkedFolderPath: nil,
        currentAccountID: nil,
        selectedAccountID: nil,
        selectedAccountIsLive: false,
        accounts: accounts,
        updatedAt: .now
    )
}

private func makeAccountRecord(
    id: String,
    name: String,
    fiveHourLimitUsedPercent: Int? = nil,
    fiveHourResetsAt: Date? = nil,
    fiveHourDataStatus: RateLimitMetricDataStatus = .missing,
    sevenDayLimitUsedPercent: Int? = nil,
    sevenDayResetsAt: Date? = nil,
    sevenDayDataStatus: RateLimitMetricDataStatus = .missing
) -> SharedCodexAccountRecord {
    SharedCodexAccountRecord(
        id: id,
        name: name,
        iconSystemName: "person.crop.circle",
        emailHint: nil,
        accountIdentifier: nil,
        authModeRaw: CodexAuthMode.chatgpt.rawValue,
        lastLoginAt: nil,
        sevenDayLimitUsedPercent: sevenDayLimitUsedPercent,
        fiveHourLimitUsedPercent: fiveHourLimitUsedPercent,
        sevenDayResetsAt: sevenDayResetsAt,
        fiveHourResetsAt: fiveHourResetsAt,
        sevenDayDataStatusRaw: sevenDayDataStatus.rawValue,
        fiveHourDataStatusRaw: fiveHourDataStatus.rawValue,
        rateLimitsObservedAt: .now,
        sortOrder: 0,
        hasLocalSnapshot: true
    )
}

private struct RecordedNotificationRequest: Equatable, Sendable {
    let identifier: String
    let title: String
    let body: String
}

private actor NotificationRequestRecorder {
    private var requests: [RecordedNotificationRequest] = []

    func value() -> [RecordedNotificationRequest] {
        return requests
    }

    func append(_ request: RecordedNotificationRequest) {
        requests.append(request)
    }
}

private final class RemovedIdentifierRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var identifiers: [String] = []

    var value: [String] {
        lock.lock()
        defer { lock.unlock() }
        return identifiers
    }

    func append(contentsOf identifiers: [String]) {
        lock.lock()
        self.identifiers.append(contentsOf: identifiers)
        lock.unlock()
    }
}
