//
//  LaunchAtLoginService.swift
//  Codex Switcher Mac App
//
//  Created by Marcel Kwiatkowski on 2026-04-09.
//

import Foundation
import ServiceManagement

struct LaunchAtLoginState: Equatable {
    let isEnabled: Bool
    let requiresApproval: Bool

    static let disabled = LaunchAtLoginState(isEnabled: false, requiresApproval: false)
}

enum LaunchAtLoginService {
    static func currentState() -> LaunchAtLoginState {
        state(for: SMAppService.mainApp.status)
    }

    static func setEnabled(_ isEnabled: Bool) throws -> LaunchAtLoginState {
        let service = SMAppService.mainApp

        switch (isEnabled, service.status) {
        case (true, .enabled), (true, .requiresApproval):
            return state(for: service.status)
        case (false, .notRegistered), (false, .notFound):
            return state(for: service.status)
        case (true, _):
            try service.register()
        case (false, _):
            try service.unregister()
        @unknown default:
            break
        }

        return currentState()
    }

    static func userFacingMessage(for error: Error) -> String {
        let nsError = error as NSError

        if nsError.domain == SMAppServiceErrorDomain {
            switch nsError.code {
            case kSMErrorLaunchDeniedByUser:
                return "macOS requires approval before Codex Switcher can launch at login. Review it in System Settings > General > Login Items."
            case kSMErrorInvalidSignature:
                return "Codex Switcher must be properly signed before macOS allows it to launch at login."
            case kSMErrorAlreadyRegistered, kSMErrorJobNotFound:
                return "The launch-at-login setting changed, but macOS was already in the requested state."
            default:
                break
            }
        }

        return error.localizedDescription
    }

    private static func state(for status: SMAppService.Status) -> LaunchAtLoginState {
        switch status {
        case .enabled:
            LaunchAtLoginState(isEnabled: true, requiresApproval: false)
        case .requiresApproval:
            LaunchAtLoginState(isEnabled: true, requiresApproval: true)
        case .notRegistered, .notFound:
            .disabled
        @unknown default:
            .disabled
        }
    }
}
