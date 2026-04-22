//
//  AppAboutInfo.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-11.
//

import Foundation

struct AppAboutInfo {
    let version: String
    let build: String

    /// User-facing version string shown consistently across platforms.
    /// Keep the build number in parentheses so support/debug instructions can
    /// ask for a single value instead of separate version/build fields.
    var formattedVersion: String {
        "\(version) (\(build))"
    }

    static var current: AppAboutInfo {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        return AppAboutInfo(version: version, build: build)
    }
}
