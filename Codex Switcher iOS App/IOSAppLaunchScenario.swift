//
//  IOSAppLaunchScenario.swift
//  Codex Switcher iOS App
//
//  Created by Codex on 2026-04-11.
//

import Foundation

enum IOSAppLaunchScenario: String {
    case empty
    case sampleData = "sample-data"

    static var current: IOSAppLaunchScenario? {
        ProcessInfo.processInfo.environment["CODEX_SWITCHER_IOS_LAUNCH_SCENARIO"]
            .flatMap(IOSAppLaunchScenario.init(rawValue:))
    }
}
