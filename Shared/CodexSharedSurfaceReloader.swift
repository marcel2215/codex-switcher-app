//
//  CodexSharedSurfaceReloader.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-08.
//

import WidgetKit

enum CodexSharedSurfaceReloader {
    nonisolated static func reloadAll() {
        WidgetCenter.shared.reloadTimelines(ofKind: CodexSharedSurfaceKinds.currentAccountWidget)
        WidgetCenter.shared.reloadTimelines(ofKind: CodexSharedSurfaceKinds.savedAccountWidget)
        ControlCenter.shared.reloadControls(ofKind: CodexSharedSurfaceKinds.quickSwitchControl)
        ControlCenter.shared.reloadControls(ofKind: CodexSharedSurfaceKinds.openAppControl)
    }
}
