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

    static func make() -> IOSAppBootstrap {
        let schema = Schema([StoredAccount.self])
        let launchScenario = IOSAppLaunchScenario.current
        let isStoredInMemoryOnly = launchScenario != nil
        let configuration = ModelConfiguration(
            "Accounts",
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly,
            cloudKitDatabase: isStoredInMemoryOnly ? .none : .automatic
        )

        do {
            let modelContainer = try ModelContainer(for: schema, configurations: [configuration])

            if let launchScenario {
                try IOSPreviewData.seed(launchScenario, into: modelContainer.mainContext)
            }

            return .ready(modelContainer)
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
