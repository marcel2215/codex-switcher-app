//
//  SharedLaunchAtLoginService.swift
//  Codex Switcher
//
//  Created by Marcel Kwiatkowski on 2026-04-10.
//

import Foundation

#if os(macOS)
import ServiceManagement

struct CodexSharedLaunchAtLoginState: Equatable, Sendable {
    let isEnabled: Bool
    let requiresApproval: Bool

    nonisolated static let disabled = CodexSharedLaunchAtLoginState(isEnabled: false, requiresApproval: false)
}

enum CodexSharedLaunchAtLoginService {
    nonisolated static func currentState() -> CodexSharedLaunchAtLoginState {
        state(for: SMAppService.mainApp.status)
    }

    nonisolated static func setEnabled(_ isEnabled: Bool) throws -> CodexSharedLaunchAtLoginState {
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

    nonisolated static func userFacingMessage(for error: Error) -> String {
        let nsError = error as NSError

        if nsError.domain == SMAppServiceErrorDomain {
            switch nsError.code {
            case kSMErrorLaunchDeniedByUser:
                return "macOS requires approval before Codex Switcher can launch at login. Review it in System Settings > General > Login Items."
            case kSMErrorInvalidSignature:
                return "Codex Switcher must be properly signed before macOS allows it to launch at login."
            case kSMErrorAlreadyRegistered, kSMErrorJobNotFound:
                return "The launch-at-login setting was already in the requested state."
            default:
                break
            }
        }

        return error.localizedDescription
    }

    private nonisolated static func state(for status: SMAppService.Status) -> CodexSharedLaunchAtLoginState {
        switch status {
        case .enabled:
            CodexSharedLaunchAtLoginState(isEnabled: true, requiresApproval: false)
        case .requiresApproval:
            CodexSharedLaunchAtLoginState(isEnabled: true, requiresApproval: true)
        case .notRegistered, .notFound:
            .disabled
        @unknown default:
            .disabled
        }
    }
}
#endif
