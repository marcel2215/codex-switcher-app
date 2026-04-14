//
//  IOSAppBootstrap.swift
//  Codex Switcher iOS App
//
//  Created by Codex on 2026-04-11.
//

import Foundation
import SwiftData

enum IOSAppBootstrap {
    case ready(ModelContainer)
    case failed(String)

    private static let schema = Schema([StoredAccount.self])

    static func make() -> IOSAppBootstrap {
        let launchScenario = IOSAppLaunchScenario.current

        do {
            let modelContainer = try makeModelContainer(
                isStoredInMemoryOnly: launchScenario != nil
            )

            if let launchScenario {
                try IOSPreviewData.seed(launchScenario, into: modelContainer.mainContext)
            }

            return .ready(modelContainer)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    static func makePersistentModelContainer() throws -> ModelContainer {
        try makeModelContainer(isStoredInMemoryOnly: false)
    }

    private static func makeModelContainer(isStoredInMemoryOnly: Bool) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "Accounts",
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly,
            cloudKitDatabase: isStoredInMemoryOnly ? .none : .automatic
        )

        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
