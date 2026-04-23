//
//  IOSPreviewData.swift
//  Codex Switcher iOS App
//
//  Created by Codex on 2026-04-11.
//

import Foundation
import SwiftData

enum IOSPreviewData {
    @MainActor
    static func makeContainer(scenario: IOSAppLaunchScenario = .sampleData) -> ModelContainer {
        let schema = Schema([StoredAccount.self])
        let configuration = ModelConfiguration(
            "PreviewAccounts",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )

        let modelContainer = try! ModelContainer(for: schema, configurations: [configuration])
        try! seed(scenario, into: modelContainer.mainContext)
        return modelContainer
    }

    @MainActor
    static func seed(_ scenario: IOSAppLaunchScenario, into modelContext: ModelContext) throws {
        try clear(modelContext)

        guard scenario == .sampleData else {
            return
        }

        modelContext.insert(
            StoredAccount(
                identityKey: "account:work",
                name: "Work",
                createdAt: .now.addingTimeInterval(-86_400 * 14),
                lastLoginAt: .now.addingTimeInterval(-60 * 45),
                customOrder: 0,
                authModeRaw: "chatgpt",
                emailHint: "work@example.com",
                accountIdentifier: "acct-work",
                sevenDayLimitUsedPercent: 88,
                fiveHourLimitUsedPercent: 61,
                rateLimitsObservedAt: .now.addingTimeInterval(-60 * 8),
                iconSystemName: AccountIconOption.briefcase.systemName
            )
        )

        modelContext.insert(
            StoredAccount(
                identityKey: "account:personal",
                name: "Personal",
                createdAt: .now.addingTimeInterval(-86_400 * 5),
                lastLoginAt: .now.addingTimeInterval(-86_400),
                customOrder: 1,
                authModeRaw: "chatgpt",
                emailHint: "personal@example.com",
                accountIdentifier: "acct-personal",
                sevenDayLimitUsedPercent: 42,
                fiveHourLimitUsedPercent: nil,
                rateLimitsObservedAt: .now.addingTimeInterval(-60 * 30),
                iconSystemName: AccountIconOption.heart.systemName
            )
        )

        try modelContext.save()
    }

    @MainActor
    private static func clear(_ modelContext: ModelContext) throws {
        let descriptor = FetchDescriptor<StoredAccount>()
        for account in try modelContext.fetch(descriptor) {
            modelContext.delete(account)
        }

        try modelContext.save()
    }
}
