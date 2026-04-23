//
//  PreviewData.swift
//  Codex Switcher Watch App
//
//  Created by Marcel Kwiatkowski on 2026-04-12.
//

import Foundation
import SwiftData

enum WatchPreviewData {
    @MainActor
    static func makeContainer() -> ModelContainer {
        let schema = Schema([StoredAccount.self])
        let configuration = ModelConfiguration(
            "WatchPreviewAccounts",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )

        let modelContainer = try! ModelContainer(for: schema, configurations: [configuration])
        let modelContext = modelContainer.mainContext

        modelContext.insert(
            StoredAccount(
                identityKey: "watch:preview:work",
                name: "Work",
                createdAt: .now.addingTimeInterval(-86_400 * 7),
                lastLoginAt: .now.addingTimeInterval(-1_800),
                customOrder: 0,
                authModeRaw: CodexAuthMode.chatgpt.rawValue,
                emailHint: "work@example.com",
                accountIdentifier: "acct-work",
                sevenDayLimitUsedPercent: 84,
                fiveHourLimitUsedPercent: 33,
                sevenDayResetsAt: .now.addingTimeInterval(60 * 60 * 18),
                fiveHourResetsAt: .now.addingTimeInterval(60 * 90),
                rateLimitsObservedAt: .now.addingTimeInterval(-60 * 2),
                iconSystemName: AccountIconOption.briefcase.systemName
            )
        )

        modelContext.insert(
            StoredAccount(
                identityKey: "watch:preview:unknown",
                name: "Unknown",
                createdAt: .now.addingTimeInterval(-86_400),
                customOrder: 1,
                authModeRaw: CodexAuthMode.chatgpt.rawValue,
                emailHint: "unknown@example.com",
                accountIdentifier: "acct-unknown",
                sevenDayLimitUsedPercent: nil,
                fiveHourLimitUsedPercent: nil,
                rateLimitsObservedAt: nil,
                iconSystemName: AccountIconOption.person.systemName
            )
        )

        try? modelContext.save()
        return modelContainer
    }
}
