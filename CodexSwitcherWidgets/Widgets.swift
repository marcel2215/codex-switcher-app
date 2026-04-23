//
//  Widgets.swift
//  Codex Switcher Widgets
//
//  Created by Marcel Kwiatkowski on 2026-04-13.
//

import WidgetKit
import SwiftUI

@main
struct Widgets: WidgetBundle {
    var body: some Widget {
        RateLimitWidget()
        RateLimitAccessory()
    }
}
