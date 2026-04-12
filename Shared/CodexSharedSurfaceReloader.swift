//
//  CodexSharedSurfaceReloader.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-08.
//

import WidgetKit

enum CodexSharedSurfaceReloader {
    nonisolated static func reloadAllRateLimitWidgets() {
        WidgetCenter.shared.reloadTimelines(ofKind: CodexSharedSurfaceKinds.rateLimitOverviewWidget)
        WidgetCenter.shared.reloadTimelines(ofKind: CodexSharedSurfaceKinds.rateLimitAccessoryWidget)
        WidgetCenter.shared.reloadTimelines(ofKind: CodexSharedSurfaceKinds.rateLimitWatchComplication)
    }

    nonisolated static func reloadAll() {
        reloadAllRateLimitWidgets()
        WidgetCenter.shared.reloadTimelines(ofKind: CodexSharedSurfaceKinds.currentAccountWidget)
        WidgetCenter.shared.reloadTimelines(ofKind: CodexSharedSurfaceKinds.savedAccountWidget)
#if !os(watchOS)
        ControlCenter.shared.reloadControls(ofKind: CodexSharedSurfaceKinds.quickSwitchControl)
        ControlCenter.shared.reloadControls(ofKind: CodexSharedSurfaceKinds.openAppControl)
#endif
    }
}
