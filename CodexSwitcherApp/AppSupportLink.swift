//
//  AppSupportLink.swift
//  Codex Switcher
//
//  Created by Marcel Kwiatkowski on 2026-04-11.
//

import Foundation
import Darwin

#if canImport(UIKit)
import UIKit
#endif

#if os(macOS)
import IOKit
#endif

enum AppSupportLink {
    @MainActor
    static var contactURL: URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmailAddress
        components.queryItems = [
            URLQueryItem(name: "subject", value: supportEmailSubject),
            URLQueryItem(name: "body", value: diagnosticEmailBody)
        ]
        return components.url!
    }

    static let websiteURL = URL(string: "https://codexswitcher.marcel2215.com")!
    static let termsOfServiceURL = URL(string: "https://codexswitcher.marcel2215.com/terms-of-service")!
    static let sourceCodeURL = URL(string: "https://github.com/marcel2215/codex-switcher-app")!
    static let privacyPolicyURL = URL(string: "https://codexswitcher.marcel2215.com/privacy-policy")!

    private static let supportEmailAddress = "marcel2215@icloud.com"
    private static var supportEmailSubject: String {
        L10n.string("Codex Switcher Support", comment: "Default subject for the support email.")
    }

    private static var supportEmailFooterFormat: String {
        L10n.string(
            "[Please keep the following: Settings · %@ · %@ · v%@ · iOS %@ · %@]",
            comment: "Diagnostic footer for support email. Preserve the bracketed format and all placeholders."
        )
    }
    private static var unknownValue: String {
        L10n.string("Unknown", comment: "Fallback diagnostic value when device metadata is unavailable.")
    }

    @MainActor
    private static var diagnosticEmailBody: String {
        let footerLine = String(
            format: supportEmailFooterFormat,
            locale: Locale.current,
            hardwareIdentifier,
            languageCode,
            AppAboutInfo.current.formattedVersion,
            operatingSystemVersion,
            hardwareModel
        )
        return "\n\n\n\(footerLine)"
    }

    @MainActor
    private static var hardwareIdentifier: String {
        #if canImport(UIKit)
        UIDevice.current.identifierForVendor?.uuidString ?? unknownValue
        #elseif os(macOS)
        macHardwareIdentifier() ?? unknownValue
        #else
        unknownValue
        #endif
    }

    private static var languageCode: String {
        Locale.current.language.languageCode?.identifier.uppercased() ?? "EN"
    }

    @MainActor
    private static var operatingSystemVersion: String {
        #if canImport(UIKit)
        return UIDevice.current.systemVersion
        #elseif os(macOS)
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        #else
        return ProcessInfo.processInfo.operatingSystemVersionString
        #endif
    }

    private static var hardwareModel: String {
        #if os(macOS)
        sysctlString(named: "hw.model") ?? unknownValue
        #else
        sysctlString(named: "hw.machine") ?? unknownValue
        #endif
    }

    private static func sysctlString(named name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }

        var value = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else {
            return nil
        }

        let bytes = value.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    #if os(macOS)
    private static func macHardwareIdentifier() -> String? {
        let platformExpert = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        guard platformExpert != 0 else {
            return nil
        }
        defer {
            IOObjectRelease(platformExpert)
        }

        return IORegistryEntryCreateCFProperty(
            platformExpert,
            "IOPlatformUUID" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? String
    }
    #endif
}
