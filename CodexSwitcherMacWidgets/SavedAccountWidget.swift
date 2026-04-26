//
//  SavedAccountWidget.swift
//  Codex Switcher Mac Widgets
//
//  Created by Marcel Kwiatkowski on 2026-04-08.
//

import AppIntents
import SwiftUI
import WidgetKit

struct SavedAccountWidgetConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Account"
    static let description = IntentDescription("Chooses which saved Codex account to show.")

    @Parameter(title: "Account")
    var account: CodexAccountEntity?
}

struct SavedAccountEntry: TimelineEntry {
    let date: Date
    let state: SharedCodexState
    let selectedAccountID: String?
}

struct SavedAccountProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SavedAccountEntry {
        SavedAccountEntry(date: .now, state: .empty, selectedAccountID: nil)
    }

    func snapshot(for configuration: SavedAccountWidgetConfigurationIntent, in context: Context) async -> SavedAccountEntry {
        SavedAccountEntry(
            date: .now,
            state: loadSharedState(),
            selectedAccountID: configuration.account?.id
        )
    }

    func timeline(for configuration: SavedAccountWidgetConfigurationIntent, in context: Context) async -> Timeline<SavedAccountEntry> {
        let entry = SavedAccountEntry(
            date: .now,
            state: loadSharedState(),
            selectedAccountID: configuration.account?.id
        )
        return Timeline(entries: [entry], policy: .never)
    }

    private func loadSharedState() -> SharedCodexState {
        CodexSharedStateStore().loadBestEffort()
    }
}

struct SavedAccountWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: CodexSharedSurfaceKinds.savedAccountWidget,
            intent: SavedAccountWidgetConfigurationIntent.self,
            provider: SavedAccountProvider()
        ) { entry in
            SavedAccountWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Saved Account")
        .description("Shows one of your saved accounts and lets you switch to it.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct SavedAccountWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: SavedAccountEntry

    private var selectedAccount: SharedCodexAccountRecord? {
        guard let selectedAccountID = entry.selectedAccountID else {
            return nil
        }

        return entry.state.account(withIdentityKey: selectedAccountID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let selectedAccount {
                Label("Saved Account", systemImage: selectedAccount.iconSystemName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(selectedAccount.name)
                    .font(family == .systemSmall ? .headline : .title3.weight(.semibold))
                    .lineLimit(2)

                if let subtitle = selectedAccount.emailHint ?? selectedAccount.accountIdentifier {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                if entry.state.authState.canAttemptSwitch {
                    Button(intent: configuredSwitchIntent(for: selectedAccount)) {
                        Label(
                            selectedAccount.id == entry.state.currentAccountID ? "Current" : "Log In",
                            systemImage: selectedAccount.id == entry.state.currentAccountID ? "checkmark.circle" : "arrow.right.circle"
                        )
                    }
                    .font(.caption)
                } else {
                    Button(intent: OpenCodexSwitcherIntent()) {
                        Label("Open", systemImage: "arrow.right.circle")
                    }
                    .font(.caption)
                }
            } else {
                Label("Choose Account", systemImage: "person.crop.rectangle.stack.badge.plus")
                    .font(.headline)

                Text("Edit this widget and select one of your saved Codex accounts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(family == .systemSmall ? 4 : 6)

                Spacer(minLength: 0)

                Button(intent: OpenCodexSwitcherIntent()) {
                    Label("Open", systemImage: "arrow.right.circle")
                }
                .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func configuredSwitchIntent(for account: SharedCodexAccountRecord) -> SwitchAccountControlIntent {
        SwitchAccountControlIntent(
            account: CodexAccountEntity(record: account, currentAccountID: entry.state.currentAccountID)
        )
    }
}
