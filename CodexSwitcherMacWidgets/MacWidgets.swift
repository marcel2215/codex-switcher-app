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
        CodexSharedStateStore().loadBestEffort()
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
        return L10n.string("Select Codex Folder", comment: "Widget title asking the user to link the Codex folder.")
    case .ready:
        return L10n.string("No Current Account", comment: "Widget title when no current account matches the linked auth file.")
    case .loggedOut:
        return L10n.string("Logged Out", comment: "Widget title when Codex has no auth file.")
    case .locationUnavailable:
        return L10n.string("Folder Missing", comment: "Widget title when the linked Codex folder is unavailable.")
    case .accessDenied:
        return L10n.string("Permission Needed", comment: "Widget title when folder permission must be granted again.")
    case .corruptAuthFile:
        return L10n.string("Invalid auth.json", comment: "Widget title when the Codex auth file is invalid.")
    case .unsupportedCredentialStore:
        return L10n.string("Unsupported Store", comment: "Widget title when the credential store is unsupported.")
    }
}

private func widgetMessage(for state: SharedCodexState) -> String {
    switch state.authState {
    case .unlinked:
        return L10n.string(
            "Open Codex Switcher and choose the Codex folder.",
            comment: "Widget message asking the user to link the Codex folder."
        )
    case .ready:
        return L10n.string(
            "Codex is linked, but no saved account matches the current auth.json.",
            comment: "Widget message when the current auth file does not match a saved account."
        )
    case .loggedOut:
        return L10n.string(
            "No auth.json was found in the linked Codex folder.",
            comment: "Widget message when Codex is logged out."
        )
    case .locationUnavailable:
        return L10n.string(
            "The linked folder is no longer available.",
            comment: "Widget message when the linked Codex folder cannot be reached."
        )
    case .accessDenied:
        return L10n.string(
            "Codex Switcher needs permission to access the linked folder again.",
            comment: "Widget message when folder permission is needed."
        )
    case .corruptAuthFile:
        return L10n.string(
            "The linked auth.json isn't valid.",
            comment: "Widget message when the linked auth file is invalid."
        )
    case .unsupportedCredentialStore:
        return L10n.string(
            "The linked folder uses an unsupported credential store.",
            comment: "Widget message when the credential store is unsupported."
        )
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
