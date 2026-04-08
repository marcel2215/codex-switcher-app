//
//  CodexSwitcherWidgetsControl.swift
//  Codex Switcher Widgets
//
//  Created by Codex on 2026-04-08.
//

import SwiftUI
import WidgetKit

struct QuickSwitchControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(
            kind: CodexSharedSurfaceKinds.quickSwitchControl,
            intent: SwitchAccountIntent.self
        ) { configuration in
            ControlWidgetButton(action: configuration) {
                Label(
                    configuration.account?.name ?? "Select Account",
                    systemImage: configuration.account?.iconSystemName ?? "arrow.left.arrow.right.circle"
                )
                .controlWidgetActionHint("Switch")
            }
        }
        .displayName("Switch Codex Account")
        .description("Switches Codex to one of your saved accounts.")
        .promptsForUserConfiguration()
    }
}
