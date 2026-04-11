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

    static var current: AppAboutInfo {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        return AppAboutInfo(version: version, build: build)
    }
}
