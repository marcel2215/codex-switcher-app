//
//  CodexWidgetIntents.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-12.
//

import AppIntents
import Foundation

enum RateLimitWindow: String, AppEnum, Codable, Sendable {
    case fiveHour
    case sevenDay

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Rate Limit Window")
    static let caseDisplayRepresentations: [RateLimitWindow: DisplayRepresentation] = [
        .fiveHour: .init(title: "5h"),
        .sevenDay: .init(title: "7d"),
    ]

    var shortLabel: String {
        switch self {
        case .fiveHour:
            "5H"
        case .sevenDay:
            "7D"
        }
    }
}

struct RateLimitOverviewConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Rate Limits"
    static let description = IntentDescription("Show selected Codex accounts and their 5h / 7d remaining limits. Any empty slot automatically uses the next account from the app's sort order.")

    @Parameter(title: "Primary Account")
    var account1: WidgetCodexAccountEntity?

    @Parameter(title: "Secondary Account")
    var account2: WidgetCodexAccountEntity?

    @Parameter(title: "Tertiary Account")
    var account3: WidgetCodexAccountEntity?

    @Parameter(title: "Quaternary Account")
    var account4: WidgetCodexAccountEntity?

    @Parameter(title: "Fifth Account")
    var account5: WidgetCodexAccountEntity?

    static var parameterSummary: some ParameterSummary {
        Switch(.widgetFamily) {
            Case(.systemSmall) {
                Summary {
                    \.$account1
                }
            }
            Case(.systemMedium) {
                Summary {
                    \.$account1
                    \.$account2
                }
            }
            DefaultCase {
                Summary {
                    \.$account1
                    \.$account2
                    \.$account3
                    \.$account4
                    \.$account5
                }
            }
        }
    }
}

struct RateLimitAccessoryConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Rate Limit"
    static let description = IntentDescription("Show one account's remaining 5h or 7d limit.")

    @Parameter(title: "Account")
    var account: WidgetCodexAccountEntity?

    @Parameter(title: "Window", default: .fiveHour)
    var window: RateLimitWindow
}
