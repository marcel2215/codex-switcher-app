//
//  CodexSwitcherWidgetsControl.swift
//  Codex Switcher Widgets
//
//  Created by Codex on 2026-04-08.
//

import SwiftUI
import WidgetKit

private struct QuickSwitchControlValue: Hashable, Sendable {
    let accountIdentityKey: String?
    let accountName: String
    let iconSystemName: String
    let isCurrent: Bool
    let isAvailable: Bool
}

private struct QuickSwitchControlValueProvider: AppIntentControlValueProvider {
    func currentValue(configuration: SwitchAccountControlIntent) async throws -> QuickSwitchControlValue {
        let state = (try? CodexSharedStateStore().load()) ?? .empty
        return makeValue(
            configuration: configuration,
            currentAccountID: state.currentAccountID,
            isPreview: false
        )
    }

    func previewValue(configuration: SwitchAccountControlIntent) -> QuickSwitchControlValue {
        makeValue(
            configuration: configuration,
            currentAccountID: nil,
            isPreview: true
        )
    }

    private func makeValue(
        configuration: SwitchAccountControlIntent,
        currentAccountID: String?,
        isPreview: Bool
    ) -> QuickSwitchControlValue {
        let account = configuration.account

        return QuickSwitchControlValue(
            accountIdentityKey: account?.id,
            accountName: account?.name ?? "Select Account",
            iconSystemName: account?.iconSystemName ?? "arrow.left.arrow.right.circle",
            isCurrent: isPreview ? false : account?.id == currentAccountID,
            isAvailable: account != nil && (account?.hasLocalSnapshot ?? false)
        )
    }
}

struct QuickSwitchControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(
            kind: CodexSharedSurfaceKinds.quickSwitchControl,
            provider: QuickSwitchControlValueProvider()
        ) { value in
            ControlWidgetToggle(
                value.accountName,
                isOn: value.isCurrent,
                action: toggleIntent(for: value)
            ) { _ in
                Image(systemName: value.iconSystemName)
            }
            .tint(.accentColor)
            .disabled(!value.isAvailable)
        }
        .displayName("Switch Codex Account")
        .description("Shows which saved account is currently active in Codex and switches accounts when turned on.")
        .promptsForUserConfiguration()
    }

    private func toggleIntent(for value: QuickSwitchControlValue) -> SelectConfiguredAccountControlIntent {
        guard let accountIdentityKey = value.accountIdentityKey else {
            return SelectConfiguredAccountControlIntent()
        }

        return SelectConfiguredAccountControlIntent(accountID: accountIdentityKey)
    }
}
