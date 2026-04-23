//
//  MacWidgets.swift
//  Codex Switcher Mac Widgets
//
//  Created by Marcel Kwiatkowski on 2026-04-08.
//

import AppIntents
import SwiftUI
import WidgetKit

struct CurrentAccountEntry: TimelineEntry {
    let date: Date
    let state: SharedCodexState
}

struct CurrentAccountProvider: TimelineProvider {
    func placeholder(in context: Context) -> CurrentAccountEntry {
        CurrentAccountEntry(date: .now, state: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (CurrentAccountEntry) -> Void) {
        completion(CurrentAccountEntry(date: .now, state: loadSharedState()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CurrentAccountEntry>) -> Void) {
        let entry = CurrentAccountEntry(date: .now, state: loadSharedState())
        completion(Timeline(entries: [entry], policy: .never))
    }

    private func loadSharedState() -> SharedCodexState {
        (try? CodexSharedStateStore().load()) ?? .empty
    }
}

struct CurrentAccountWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: CodexSharedSurfaceKinds.currentAccountWidget,
            provider: CurrentAccountProvider()
        ) { entry in
            CurrentAccountWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Current Account")
        .description("Shows the Codex account currently active on this Mac.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct CurrentAccountWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: CurrentAccountEntry

    private var currentAccount: SharedCodexAccountRecord? {
        guard let currentAccountID = entry.state.currentAccountID else {
            return nil
        }

        return entry.state.account(withIdentityKey: currentAccountID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let currentAccount {
                Label("Current Account", systemImage: currentAccount.iconSystemName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(currentAccount.name)
                    .font(family == .systemSmall ? .headline : .title3.weight(.semibold))
                    .lineLimit(2)

                if let subtitle = currentAccount.emailHint ?? currentAccount.accountIdentifier {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                Button(intent: OpenCodexSwitcherIntent()) {
                    Label("Open", systemImage: "arrow.right.circle")
                }
                .font(.caption)
            } else {
                widgetFallback
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var widgetFallback: some View {
        Label(widgetTitle(for: entry.state.authState), systemImage: fallbackSymbol(for: entry.state.authState))
            .font(.headline)

        Text(widgetMessage(for: entry.state))
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

private func widgetTitle(for authState: SharedCodexAuthState) -> String {
    switch authState {
    case .unlinked:
        return "Select Codex Folder"
    case .ready:
        return "No Current Account"
    case .loggedOut:
        return "Logged Out"
    case .locationUnavailable:
        return "Folder Missing"
    case .accessDenied:
        return "Permission Needed"
    case .corruptAuthFile:
        return "Invalid auth.json"
    case .unsupportedCredentialStore:
        return "Unsupported Store"
    }
}

private func widgetMessage(for state: SharedCodexState) -> String {
    switch state.authState {
    case .unlinked:
        return "Open Codex Switcher and choose the Codex folder."
    case .ready:
        return "Codex is linked, but no saved account matches the current auth.json."
    case .loggedOut:
        return "No auth.json was found in the linked Codex folder."
    case .locationUnavailable:
        return "The linked folder is no longer available."
    case .accessDenied:
        return "Codex Switcher needs permission to access the linked folder again."
    case .corruptAuthFile:
        return "The linked auth.json isn't valid."
    case .unsupportedCredentialStore:
        return "The linked folder uses an unsupported credential store."
    }
}

private func fallbackSymbol(for authState: SharedCodexAuthState) -> String {
    switch authState {
    case .unlinked:
        return "folder.badge.questionmark"
    case .ready:
        return "person.crop.rectangle.stack"
    case .loggedOut:
        return "person.crop.rectangle.stack.badge.minus"
    case .locationUnavailable:
        return "folder.badge.minus"
    case .accessDenied:
        return "lock.slash"
    case .corruptAuthFile:
        return "exclamationmark.triangle"
    case .unsupportedCredentialStore:
        return "key.slash"
    }
}
