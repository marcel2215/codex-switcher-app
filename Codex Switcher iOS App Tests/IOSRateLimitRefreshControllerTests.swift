//
//  IOSRateLimitRefreshControllerTests.swift
//  Codex Switcher iOS AppTests
//
//  Created by Codex on 2026-04-11.
//

import BackgroundTasks
import Foundation
import SwiftData
import Testing
import UIKit
@testable import Codex_Switcher_iOS_App

@MainActor
struct IOSRateLimitRefreshControllerTests {
    @Test
    func visibleRefreshUsesSyncedCredentialsAndUpdatesStoredAccount() async throws {
        let account = makeRefreshTestAccount(
            identityKey: "identity-work",
            name: "Work",
            customOrder: 0
        )
        let harness = try makeRefreshHarness(accounts: [account])
        let provider = TestIOSRateLimitProvider()
        let credentialStore = TestSyncedRateLimitCredentialStore()
        let controller = IOSRateLimitRefreshController(
            provider: provider,
            credentialStore: credentialStore
        )
        let observedAt = Date().addingTimeInterval(-30)
        let snapshot = makeRefreshSnapshot(
            identityKey: account.identityKey,
            observedAt: observedAt,
            fetchedAt: observedAt.addingTimeInterval(5),
            sevenDayRemainingPercent: 84,
            fiveHourRemainingPercent: 33
        )

        try await credentialStore.save(
            SyncedRateLimitCredential(
                credentials: CodexRateLimitCredentials(
                    identityKey: account.identityKey,
                    authMode: .chatgpt,
                    accountID: "acct-work",
                    accessToken: "token-work",
                    idToken: nil
                )
            )
        )
        await provider.setSnapshot(snapshot, for: account.identityKey)

        controller.configure(modelContext: harness.modelContext)
        controller.setVisible(true, for: account.identityKey)

        try await waitUntil {
            await provider.requestCount(for: account.identityKey) == 1
        }

        let refreshedAccount = try #require(fetchRefreshAccounts(in: harness.modelContext).first)
        #expect(refreshedAccount.sevenDayLimitUsedPercent == 84)
        #expect(refreshedAccount.fiveHourLimitUsedPercent == 33)
        #expect(refreshedAccount.rateLimitsObservedAt == snapshot.observedAt)
    }

    @Test
    func selectedAccountRefreshesMoreAggressivelyThanVisibleRows() async throws {
        let observedAt = Date().addingTimeInterval(-120)
        let account = makeRefreshTestAccount(
            identityKey: "identity-selected",
            name: "Selected",
            customOrder: 0,
            sevenDayLimitUsedPercent: 50,
            fiveHourLimitUsedPercent: 50,
            rateLimitsObservedAt: observedAt
        )
        let harness = try makeRefreshHarness(accounts: [account])
        let provider = TestIOSRateLimitProvider()
        let credentialStore = TestSyncedRateLimitCredentialStore()
        let controller = IOSRateLimitRefreshController(
            provider: provider,
            credentialStore: credentialStore
        )

        try await credentialStore.save(
            SyncedRateLimitCredential(
                credentials: CodexRateLimitCredentials(
                    identityKey: account.identityKey,
                    authMode: .chatgpt,
                    accountID: "acct-selected",
                    accessToken: "token-selected",
                    idToken: nil
                )
            )
        )
        await provider.setSnapshot(makeRefreshSnapshot(identityKey: account.identityKey), for: account.identityKey)

        controller.configure(modelContext: harness.modelContext)
        controller.setVisible(true, for: account.identityKey)
        await controller.refreshNowForTesting(for: account.identityKey)
        #expect(await provider.requestCount(for: account.identityKey) == 1)
        await provider.resetRequests()

        // A visible list row that was refreshed two minutes ago is still fresh.
        account.rateLimitsObservedAt = observedAt
        try harness.modelContext.save()
        await provider.setSnapshot(makeRefreshSnapshot(identityKey: account.identityKey), for: account.identityKey)
        await provider.resetRequests()
        controller.reconcileKnownIdentityKeys([account.identityKey])
        await controller.refreshDueAccountsForTesting()
        #expect(await provider.requestCount(for: account.identityKey) == 0)

        // Selecting the same account should refresh immediately.
        controller.setSelected(identityKey: account.identityKey)
        try await waitUntil {
            await provider.requestCount(for: account.identityKey) == 1
        }
    }

    @Test
    func unauthorizedBackoffWaitsForCredentialFingerprintChange() async throws {
        let account = makeRefreshTestAccount(
            identityKey: "identity-auth",
            name: "Auth",
            customOrder: 0
        )
        let harness = try makeRefreshHarness(accounts: [account])
        let provider = TestIOSRateLimitProvider()
        let credentialStore = TestSyncedRateLimitCredentialStore()
        let controller = IOSRateLimitRefreshController(
            provider: provider,
            credentialStore: credentialStore
        )

        try await credentialStore.save(
            SyncedRateLimitCredential(
                credentials: CodexRateLimitCredentials(
                    identityKey: account.identityKey,
                    authMode: .chatgpt,
                    accountID: "acct-auth",
                    accessToken: "token-1",
                    idToken: nil
                )
            )
        )
        await provider.setFailure(.unauthorized, for: account.identityKey)

        controller.configure(modelContext: harness.modelContext)
        await controller.refreshNowForTesting(for: account.identityKey)
        #expect(await provider.requestCount(for: account.identityKey) == 1)

        await controller.refreshNowForTesting(for: account.identityKey)
        #expect(await provider.requestCount(for: account.identityKey) == 1)

        try await credentialStore.save(
            SyncedRateLimitCredential(
                credentials: CodexRateLimitCredentials(
                    identityKey: account.identityKey,
                    authMode: .chatgpt,
                    accountID: "acct-auth",
                    accessToken: "token-2",
                    idToken: nil
                )
            )
        )

        await controller.refreshNowForTesting(for: account.identityKey)
        #expect(await provider.requestCount(for: account.identityKey) == 2)
    }

    @Test
    func missingSyncedCredentialLeavesExistingValuesUntouched() async throws {
        let observedAt = Date(timeIntervalSince1970: 2_000)
        let account = makeRefreshTestAccount(
            identityKey: "identity-missing",
            name: "Missing",
            customOrder: 0,
            sevenDayLimitUsedPercent: 91,
            fiveHourLimitUsedPercent: 64,
            rateLimitsObservedAt: observedAt
        )
        let harness = try makeRefreshHarness(accounts: [account])
        let provider = TestIOSRateLimitProvider()
        let controller = IOSRateLimitRefreshController(
            provider: provider,
            credentialStore: TestSyncedRateLimitCredentialStore()
        )

        controller.configure(modelContext: harness.modelContext)
        await controller.refreshNowForTesting(for: account.identityKey)

        let unchangedAccount = try #require(fetchRefreshAccounts(in: harness.modelContext).first)
        #expect(await provider.requestCount(for: account.identityKey) == 0)
        #expect(unchangedAccount.sevenDayLimitUsedPercent == 91)
        #expect(unchangedAccount.fiveHourLimitUsedPercent == 64)
        #expect(unchangedAccount.rateLimitsObservedAt == observedAt)
    }

    @Test
    func automaticRefreshHonorsTransientBackoff() async throws {
        let account = makeRefreshTestAccount(
            identityKey: "identity-backoff",
            name: "Backoff",
            customOrder: 0
        )
        let harness = try makeRefreshHarness(accounts: [account])
        let provider = TestIOSRateLimitProvider()
        let credentialStore = TestSyncedRateLimitCredentialStore()
        let controller = IOSRateLimitRefreshController(
            provider: provider,
            credentialStore: credentialStore
        )

        try await credentialStore.save(
            SyncedRateLimitCredential(
                credentials: CodexRateLimitCredentials(
                    identityKey: account.identityKey,
                    authMode: .chatgpt,
                    accountID: "acct-backoff",
                    accessToken: "token-backoff",
                    idToken: nil
                )
            )
        )
        await provider.setFailure(.network(.notConnectedToInternet), for: account.identityKey)

        controller.configure(modelContext: harness.modelContext)
        controller.setVisible(true, for: account.identityKey)
        try await waitUntil {
            await provider.requestCount(for: account.identityKey) == 1
        }

        controller.setVisible(false, for: account.identityKey)
        controller.setVisible(true, for: account.identityKey)
        try? await Task.sleep(nanoseconds: 100_000_000)

        #expect(await provider.requestCount(for: account.identityKey) == 1)
    }

    @Test
    func credentialFingerprintChangeRetriesDuringPollingBeforeAuthBackoffExpires() async throws {
        let observedAt = Date()
        let account = makeRefreshTestAccount(
            identityKey: "identity-auth-refresh",
            name: "Auth Refresh",
            customOrder: 0,
            sevenDayLimitUsedPercent: 70,
            fiveHourLimitUsedPercent: 42,
            rateLimitsObservedAt: observedAt
        )
        let harness = try makeRefreshHarness(accounts: [account])
        let provider = TestIOSRateLimitProvider()
        let credentialStore = TestSyncedRateLimitCredentialStore()
        let controller = IOSRateLimitRefreshController(
            provider: provider,
            credentialStore: credentialStore
        )

        try await credentialStore.save(
            SyncedRateLimitCredential(
                credentials: CodexRateLimitCredentials(
                    identityKey: account.identityKey,
                    authMode: .chatgpt,
                    accountID: "acct-auth-refresh",
                    accessToken: "token-old",
                    idToken: nil
                )
            )
        )
        await provider.setFailure(.unauthorized, for: account.identityKey)

        controller.configure(modelContext: harness.modelContext)
        controller.setVisible(true, for: account.identityKey)
        await controller.refreshNowForTesting(for: account.identityKey)
        #expect(await provider.requestCount(for: account.identityKey) == 1)
        await provider.resetRequests()

        try await credentialStore.save(
            SyncedRateLimitCredential(
                credentials: CodexRateLimitCredentials(
                    identityKey: account.identityKey,
                    authMode: .chatgpt,
                    accountID: "acct-auth-refresh",
                    accessToken: "token-new",
                    idToken: nil
                )
            )
        )
        await provider.setSnapshot(
            makeRefreshSnapshot(
                identityKey: account.identityKey,
                observedAt: observedAt.addingTimeInterval(30),
                fetchedAt: observedAt.addingTimeInterval(35),
                sevenDayRemainingPercent: 67,
                fiveHourRemainingPercent: 40
            ),
            for: account.identityKey
        )

        await controller.refreshDueAccountsForTesting()

        #expect(await provider.requestCount(for: account.identityKey) == 1)
    }

    @Test
    func duplicateIdentityKeysRefreshAllMatchingAccounts() async throws {
        let duplicateIdentityKey = "identity-duplicate"
        let firstAccount = makeRefreshTestAccount(
            identityKey: duplicateIdentityKey,
            name: "Duplicate A",
            customOrder: 0
        )
        let secondAccount = makeRefreshTestAccount(
            identityKey: duplicateIdentityKey,
            name: "Duplicate B",
            customOrder: 1
        )
        let harness = try makeRefreshHarness(accounts: [firstAccount, secondAccount])
        let provider = TestIOSRateLimitProvider()
        let credentialStore = TestSyncedRateLimitCredentialStore()
        let controller = IOSRateLimitRefreshController(
            provider: provider,
            credentialStore: credentialStore
        )

        try await credentialStore.save(
            SyncedRateLimitCredential(
                credentials: CodexRateLimitCredentials(
                    identityKey: duplicateIdentityKey,
                    authMode: .chatgpt,
                    accountID: "acct-duplicate",
                    accessToken: "token-duplicate",
                    idToken: nil
                )
            )
        )
        await provider.setSnapshot(makeRefreshSnapshot(identityKey: duplicateIdentityKey), for: duplicateIdentityKey)

        controller.configure(modelContext: harness.modelContext)
        controller.setVisible(true, for: duplicateIdentityKey)
        try await waitUntil {
            await provider.requestCount(for: duplicateIdentityKey) == 1
        }

        let remainingAccounts = try fetchRefreshAccounts(in: harness.modelContext)
            .filter { $0.identityKey == duplicateIdentityKey }
        #expect(remainingAccounts.count == 2)
        #expect(remainingAccounts.allSatisfy { $0.sevenDayLimitUsedPercent == 92 })
        #expect(remainingAccounts.allSatisfy { $0.fiveHourLimitUsedPercent == 44 })
        #expect(remainingAccounts.allSatisfy { $0.sevenDayResetsAt != nil })
        #expect(remainingAccounts.allSatisfy { $0.fiveHourResetsAt != nil })
    }

    @Test
    func cancelledRefreshDoesNotCreateBackoff() async throws {
        let account = makeRefreshTestAccount(
            identityKey: "identity-cancelled",
            name: "Cancelled",
            customOrder: 0
        )
        let harness = try makeRefreshHarness(accounts: [account])
        let provider = TestIOSRateLimitProvider()
        let credentialStore = TestSyncedRateLimitCredentialStore()
        let controller = IOSRateLimitRefreshController(
            provider: provider,
            credentialStore: credentialStore
        )

        try await credentialStore.save(
            SyncedRateLimitCredential(
                credentials: CodexRateLimitCredentials(
                    identityKey: account.identityKey,
                    authMode: .chatgpt,
                    accountID: "acct-cancelled",
                    accessToken: "token-cancelled",
                    idToken: nil
                )
            )
        )
        await provider.setFailure(.cancelled, for: account.identityKey)

        controller.configure(modelContext: harness.modelContext)
        await controller.refreshNowForTesting(for: account.identityKey)
        await controller.refreshNowForTesting(for: account.identityKey)

        #expect(await provider.requestCount(for: account.identityKey) == 2)
    }

    @Test
    func backgroundRefreshUpdatesAccountsAndPublishesSnapshot() async throws {
        let account = makeRefreshTestAccount(
            identityKey: "identity-background",
            name: "Background",
            customOrder: 0
        )
        let harness = try makeRefreshHarness(accounts: [account])
        let provider = TestIOSRateLimitProvider()
        let credentialStore = TestSyncedRateLimitCredentialStore()
        let publishedSnapshot = PublishedSnapshotSpy()
        let coordinator = IOSBackgroundAppRefreshCoordinator(
            provider: provider,
            credentialStore: credentialStore,
            backgroundRefreshStatusProvider: { .available },
            submitRequest: { _ in },
            cancelRequest: { _ in },
            publishSnapshot: { _ in
                publishedSnapshot.markPublished()
            }
        )
        let observedAt = Date().addingTimeInterval(-15)
        let snapshot = makeRefreshSnapshot(
            identityKey: account.identityKey,
            observedAt: observedAt,
            fetchedAt: observedAt.addingTimeInterval(5),
            sevenDayRemainingPercent: 77,
            fiveHourRemainingPercent: 28
        )

        try await credentialStore.save(
            SyncedRateLimitCredential(
                credentials: CodexRateLimitCredentials(
                    identityKey: account.identityKey,
                    authMode: .chatgpt,
                    accountID: "acct-background",
                    accessToken: "token-background",
                    idToken: nil
                )
            )
        )
        await provider.setSnapshot(snapshot, for: account.identityKey)

        let success = await coordinator.performRefresh(using: harness.modelContainer)

        #expect(success)
        #expect(await provider.requestCount(for: account.identityKey) == 1)
        #expect(publishedSnapshot.wasPublished)

        let refreshedAccount = try #require(fetchRefreshAccounts(in: harness.modelContext).first)
        #expect(refreshedAccount.sevenDayLimitUsedPercent == 77)
        #expect(refreshedAccount.fiveHourLimitUsedPercent == 28)
        #expect(refreshedAccount.rateLimitsObservedAt == snapshot.observedAt)
    }

    @Test
    func scheduleNextRefreshSubmitsAppRefreshRequestWhenAvailable() async {
        let submittedRequest = SubmittedBackgroundRequestSpy()
        let cancelledIdentifiers = CancelledBackgroundRequestsSpy()
        let coordinator = IOSBackgroundAppRefreshCoordinator(
            provider: TestIOSRateLimitProvider(),
            credentialStore: TestSyncedRateLimitCredentialStore(),
            backgroundRefreshStatusProvider: { .available },
            submitRequest: { request in
                submittedRequest.store(request)
            },
            cancelRequest: { identifier in
                cancelledIdentifiers.append(identifier)
            },
            publishSnapshot: { _ in }
        )

        coordinator.scheduleNextRefresh(after: 600)

        let request = try? #require(submittedRequest.value)
        #expect(request?.identifier == IOSBackgroundAppRefreshCoordinator.taskIdentifier)
        #expect(cancelledIdentifiers.value == [IOSBackgroundAppRefreshCoordinator.taskIdentifier])
        #expect((request?.earliestBeginDate?.timeIntervalSinceNow ?? 0) > 0)
    }
}

@MainActor
private func makeRefreshHarness(accounts: [StoredAccount]) throws -> RefreshHarness {
    let schema = Schema([StoredAccount.self])
    let configuration = ModelConfiguration(
        "RateLimitRefreshTests-\(UUID().uuidString)",
        schema: schema,
        isStoredInMemoryOnly: true,
        cloudKitDatabase: .none
    )
    let modelContainer = try ModelContainer(for: schema, configurations: [configuration])
    let modelContext = modelContainer.mainContext

    for account in accounts {
        modelContext.insert(account)
    }

    try modelContext.save()
    return RefreshHarness(
        modelContainer: modelContainer,
        modelContext: modelContext
    )
}

@MainActor
private func fetchRefreshAccounts(in modelContext: ModelContext) throws -> [StoredAccount] {
    try modelContext.fetch(FetchDescriptor<StoredAccount>())
}

private func makeRefreshTestAccount(
    identityKey: String,
    name: String,
    customOrder: Double,
    sevenDayLimitUsedPercent: Int? = nil,
    fiveHourLimitUsedPercent: Int? = nil,
    rateLimitsObservedAt: Date? = nil
) -> StoredAccount {
    StoredAccount(
        identityKey: identityKey,
        name: name,
        createdAt: .now,
        customOrder: customOrder,
        authModeRaw: CodexAuthMode.chatgpt.rawValue,
        emailHint: "\(name.lowercased())@example.com",
        accountIdentifier: "acct-\(name.lowercased())",
        sevenDayLimitUsedPercent: sevenDayLimitUsedPercent,
        fiveHourLimitUsedPercent: fiveHourLimitUsedPercent,
        rateLimitsObservedAt: rateLimitsObservedAt
    )
}

private func makeRefreshSnapshot(
    identityKey: String,
    observedAt: Date = .now,
    fetchedAt: Date = .now,
    sevenDayRemainingPercent: Int = 92,
    fiveHourRemainingPercent: Int = 44
) -> CodexRateLimitSnapshot {
    CodexRateLimitSnapshot(
        identityKey: identityKey,
        observedAt: observedAt,
        fetchedAt: fetchedAt,
        source: .remoteUsageAPI,
        sevenDayRemainingPercent: sevenDayRemainingPercent,
        fiveHourRemainingPercent: fiveHourRemainingPercent,
        sevenDayResetsAt: observedAt.addingTimeInterval(7 * 24 * 60 * 60),
        fiveHourResetsAt: observedAt.addingTimeInterval(5 * 60 * 60)
    )
}

private struct RefreshHarness {
    let modelContainer: ModelContainer
    let modelContext: ModelContext
}

private actor TestIOSRateLimitProvider: CodexRateLimitProviding {
    private var resultsByIdentityKey: [String: CodexRateLimitFetchResult] = [:]
    private var requestsByIdentityKey: [String: Int] = [:]

    func fetchSnapshot(for request: CodexRateLimitRequest) async -> CodexRateLimitFetchResult {
        requestsByIdentityKey[request.identityKey, default: 0] += 1
        return resultsByIdentityKey[request.identityKey] ?? CodexRateLimitFetchResult(remoteFailure: .missingCredentials)
    }

    func setSnapshot(_ snapshot: CodexRateLimitSnapshot, for identityKey: String) {
        resultsByIdentityKey[identityKey] = CodexRateLimitFetchResult(snapshot: snapshot)
    }

    func setFailure(_ failure: CodexRateLimitFetchFailure, for identityKey: String) {
        resultsByIdentityKey[identityKey] = CodexRateLimitFetchResult(remoteFailure: failure)
    }

    func requestCount(for identityKey: String) -> Int {
        requestsByIdentityKey[identityKey, default: 0]
    }

    func resetRequests() {
        requestsByIdentityKey.removeAll()
    }
}

private actor TestSyncedRateLimitCredentialStore: SyncedRateLimitCredentialStoring {
    private var credentialsByIdentityKey: [String: SyncedRateLimitCredential] = [:]

    func save(_ credential: SyncedRateLimitCredential) async throws {
        credentialsByIdentityKey[credential.identityKey] = credential
    }

    func load(forIdentityKey identityKey: String) async throws -> SyncedRateLimitCredential {
        guard let credential = credentialsByIdentityKey[identityKey] else {
            throw SyncedRateLimitCredentialStoreError.missingCredential
        }

        return credential
    }

    func delete(forIdentityKey identityKey: String) async throws {
        credentialsByIdentityKey.removeValue(forKey: identityKey)
    }

    func containsCredential(forIdentityKey identityKey: String) async -> Bool {
        credentialsByIdentityKey[identityKey] != nil
    }
}

private final class PublishedSnapshotSpy: @unchecked Sendable {
    private let lock = NSLock()
    private var published = false

    func markPublished() {
        lock.lock()
        published = true
        lock.unlock()
    }

    var wasPublished: Bool {
        lock.lock()
        let value = published
        lock.unlock()
        return value
    }
}

private final class SubmittedBackgroundRequestSpy: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: BGAppRefreshTaskRequest?

    func store(_ request: BGAppRefreshTaskRequest) {
        lock.lock()
        storedValue = request
        lock.unlock()
    }

    var value: BGAppRefreshTaskRequest? {
        lock.lock()
        let value = storedValue
        lock.unlock()
        return value
    }
}

private final class CancelledBackgroundRequestsSpy: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: [String] = []

    func append(_ identifier: String) {
        lock.lock()
        storedValue.append(identifier)
        lock.unlock()
    }

    var value: [String] {
        lock.lock()
        let value = storedValue
        lock.unlock()
        return value
    }
}

private struct TestRefreshTimeoutError: Error {}

private func waitUntil(
    iterations: Int = 400,
    sleepMilliseconds: UInt64 = 0,
    condition: @escaping () async -> Bool
) async throws {
    for _ in 0..<iterations {
        if await condition() {
            return
        }

        if sleepMilliseconds == 0 {
            await Task.yield()
        } else {
            try? await Task.sleep(nanoseconds: sleepMilliseconds * 1_000_000)
        }
    }

    throw TestRefreshTimeoutError()
}
