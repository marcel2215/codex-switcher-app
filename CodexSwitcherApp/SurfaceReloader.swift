//
//  SurfaceReloader.swift
//  Codex Switcher
//
//  Created by Marcel Kwiatkowski on 2026-04-08.
//

import WidgetKit

enum CodexSharedSurfaceReloader {
    nonisolated static func reloadAllRateLimitWidgets() {
        WidgetCenter.shared.invalidateConfigurationRecommendations()
        WidgetCenter.shared.reloadTimelines(ofKind: CodexSharedSurfaceKinds.rateLimitOverviewWidget)
        WidgetCenter.shared.reloadTimelines(ofKind: CodexSharedSurfaceKinds.rateLimitAccessoryWidget)
        WidgetCenter.shared.reloadTimelines(ofKind: CodexSharedSurfaceKinds.rateLimitWatchComplication)
        WidgetCenter.shared.reloadTimelines(ofKind: CodexSharedSurfaceKinds.rateLimitWatchComplicationFiveHour)
        WidgetCenter.shared.reloadTimelines(ofKind: CodexSharedSurfaceKinds.rateLimitWatchComplicationSevenDay)
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
