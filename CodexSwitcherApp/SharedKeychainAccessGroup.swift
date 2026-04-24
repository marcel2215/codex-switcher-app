//
//  SharedKeychainAccessGroup.swift
//  Codex Switcher
//
//  Created by Marcel Kwiatkowski on 2026-04-24.
//

import Foundation
#if os(macOS)
import Security
#endif

enum CodexSharedKeychainAccessGroup {
    private nonisolated static let infoPlistKey = "CodexSharedKeychainAccessGroup"

    nonisolated static var identifier: String {
        if let configuredIdentifier = Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String {
            let trimmedIdentifier = configuredIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)

            if !trimmedIdentifier.isEmpty, !trimmedIdentifier.contains("$(") {
                return trimmedIdentifier
            }
        }

        #if os(macOS)
        if let prefix = applicationIdentifierPrefix() {
            return "\(prefix)\(CodexSharedAppGroup.identifier)"
        }
        #endif

        return CodexSharedAppGroup.identifier
    }

    #if os(macOS)
    private nonisolated static func applicationIdentifierPrefix() -> String? {
        let entitlementNames = [
            "application-identifier",
            "com.apple.application-identifier",
        ]

        for entitlementName in entitlementNames {
            guard
                let task = SecTaskCreateFromSelf(nil),
                let applicationIdentifier = SecTaskCopyValueForEntitlement(
                    task,
                    entitlementName as CFString,
                    nil
                ) as? String,
                let prefix = prefix(fromApplicationIdentifier: applicationIdentifier)
            else {
                continue
            }

            return prefix
        }

        return nil
    }

    private nonisolated static func prefix(fromApplicationIdentifier applicationIdentifier: String) -> String? {
        if let bundleIdentifier = Bundle.main.bundleIdentifier,
           applicationIdentifier.hasSuffix(bundleIdentifier) {
            let prefix = String(applicationIdentifier.dropLast(bundleIdentifier.count))
            return prefix.isEmpty ? nil : prefix
        }

        guard let dotIndex = applicationIdentifier.firstIndex(of: ".") else {
            return nil
        }

        return String(applicationIdentifier[...dotIndex])
    }
    #endif
}
