//
//  CodexSwitcherWidgetsBundle.swift
//  Codex Switcher Widgets
//
//  Created by Marcel Kwiatkowski on 2026-04-08.
//

import WidgetKit
import SwiftUI

@main
struct CodexSwitcherWidgetsBundle: WidgetBundle {
    var body: some Widget {
        RateLimitOverviewWidget()
        QuickSwitchControl()
        OpenCodexSwitcherControl()
    }
}
