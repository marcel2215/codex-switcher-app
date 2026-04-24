//
//  MacWidgetBundle.swift
//  Codex Switcher Mac Widgets
//
//  Created by Marcel Kwiatkowski on 2026-04-08.
//

import WidgetKit
import SwiftUI

@main
struct MacWidgetBundle: WidgetBundle {
    var body: some Widget {
        CurrentAccountWidget()
        SavedAccountWidget()
        RateLimitOverviewWidget()
        QuickSwitchControl()
        OpenCodexSwitcherControl()
    }
}
