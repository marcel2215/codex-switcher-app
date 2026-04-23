//
//  OpenAppControl.swift
//  Codex Switcher Widgets
//
//  Created by Codex on 2026-04-08.
//

import SwiftUI
import WidgetKit

struct OpenCodexSwitcherControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: CodexSharedSurfaceKinds.openAppControl) {
            ControlWidgetButton(action: OpenCodexSwitcherIntent()) {
                Label("Open Codex Switcher", systemImage: "arrow.left.arrow.right.circle")
                    .controlWidgetActionHint("Open")
            }
        }
        .displayName("Open Codex Switcher")
        .description("Opens the app to manage accounts and relink the Codex folder.")
    }
}
