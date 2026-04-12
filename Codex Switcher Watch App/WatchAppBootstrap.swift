//
//  WatchAppBootstrap.swift
//  Codex Switcher Watch App
//
//  Created by Codex on 2026-04-12.
//

import Foundation
import SwiftData

enum WatchAppBootstrap {
    case ready(ModelContainer)
    case failed(String)

    static func make(isStoredInMemoryOnly: Bool = false) -> WatchAppBootstrap {
        let schema = Schema([StoredAccount.self])
        let configuration = ModelConfiguration(
            "Accounts",
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly,
            cloudKitDatabase: isStoredInMemoryOnly ? .none : .automatic
        )

        do {
            return .ready(try ModelContainer(for: schema, configurations: [configuration]))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    var modelContainerForPreview: ModelContainer {
        switch self {
        case let .ready(modelContainer):
            modelContainer
        case .failed:
            WatchPreviewData.makeContainer()
        }
    }
}
