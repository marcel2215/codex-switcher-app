//
//  CodexSwitcheriOSWidgetsBundle.swift
//  Codex Switcher iOS Widgets
//
//  Created by Marcel Kwiatkowski on 2026-04-13.
//

import WidgetKit
import SwiftUI

@main
struct CodexSwitcheriOSWidgetsBundle: WidgetBundle {
    var body: some Widget {
        IOSRateLimitOverviewWidget()
        IOSRateLimitAccessoryWidget()
    }
}
