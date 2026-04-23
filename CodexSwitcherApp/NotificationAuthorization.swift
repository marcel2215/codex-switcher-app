//
//  NotificationAuthorization.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-13.
//

@preconcurrency import UserNotifications

enum NotificationAuthorizationRequestResult: Equatable {
    case enabled
    case denied
    case failed(String)
}

enum CodexNotificationAuthorization {
    nonisolated static func requestAuthorizationIfNeeded(
        center: UNUserNotificationCenter = .current()
    ) async -> NotificationAuthorizationRequestResult {
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional:
            guard !settings.providesAppNotificationSettings else {
                return .enabled
            }

            return await requestAuthorization(center: center)
        case .denied, .ephemeral:
            return .denied
        case .notDetermined:
            return await requestAuthorization(center: center)
        @unknown default:
            return .failed("The system returned an unknown notification authorization state.")
        }
    }

    /// Existing installs may already be authorized without having opted into
    /// the system's in-app notification settings entry point. Re-register the
    /// authorization options on launch so the system can surface that link
    /// without forcing the user through a second prompt.
    nonisolated static func ensureProvidesAppNotificationSettingsIfAuthorized(
        center: UNUserNotificationCenter = .current()
    ) async {
        let settings = await center.notificationSettings()

        guard settings.authorizationStatus == .authorized,
              !settings.providesAppNotificationSettings
        else {
            return
        }

        _ = try? await center.requestAuthorization(options: authorizationOptions)
    }

    nonisolated static func isDeliveryAuthorized(_ status: UNAuthorizationStatus) -> Bool {
        status == .authorized || status == .provisional
    }

    private nonisolated static var authorizationOptions: UNAuthorizationOptions {
        [.alert, .providesAppNotificationSettings]
    }

    private nonisolated static func requestAuthorization(
        center: UNUserNotificationCenter
    ) async -> NotificationAuthorizationRequestResult {
        do {
            let isGranted = try await center.requestAuthorization(options: authorizationOptions)
            return isGranted ? .enabled : .denied
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
