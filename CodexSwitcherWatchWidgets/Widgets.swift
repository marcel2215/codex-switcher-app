//
//  Widgets.swift
//  Codex Switcher Watch Widgets
//
//  Created by Marcel Kwiatkowski on 2026-04-14.
//

import WidgetKit
import SwiftUI

@main
struct Widgets: WidgetBundle {
    var body: some Widget {
        OpenAppComplication()
        RateLimitComplication()
    }
}
