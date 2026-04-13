//
//  CodexNotificationAuthorization.swift
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
            return .enabled
        case .denied, .ephemeral:
            return .denied
        case .notDetermined:
            do {
                let isGranted = try await center.requestAuthorization(options: [.alert])
                return isGranted ? .enabled : .denied
            } catch {
                return .failed(error.localizedDescription)
            }
        @unknown default:
            return .failed("The system returned an unknown notification authorization state.")
        }
    }

    nonisolated static func isDeliveryAuthorized(_ status: UNAuthorizationStatus) -> Bool {
        status == .authorized || status == .provisional
    }
}
