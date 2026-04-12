//
//  Codex_Switcher_iOS_WidgetsBundle.swift
//  Codex Switcher iOS Widgets
//
//  Created by Codex on 2026-04-12.
//

import SwiftUI
import WidgetKit

@main
struct Codex_Switcher_iOS_WidgetsBundle: WidgetBundle {
    var body: some Widget {
        RateLimitOverviewWidget()
        RateLimitAccessoryWidget()
    }
}
