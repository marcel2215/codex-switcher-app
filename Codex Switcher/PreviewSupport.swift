//
//  PreviewSupport.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-07.
//

import Foundation
import SwiftData

enum PreviewData {
    @MainActor
    static func makeContainer() -> ModelContainer {
        let schema = Schema([StoredAccount.self])
        let configuration = ModelConfiguration(
            "PreviewAccounts",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )

        let container = try! ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext

        context.insert(
            StoredAccount(
                identityKey: "account:preview-one",
                name: "Account 1",
                createdAt: .now.addingTimeInterval(-86_400),
                lastLoginAt: .now.addingTimeInterval(-3_600),
                customOrder: 0,
                authModeRaw: CodexAuthMode.chatgpt.rawValue,
                emailHint: "preview-one@example.com",
                accountIdentifier: "preview-one",
                sevenDayLimitUsedPercent: 93,
                fiveHourLimitUsedPercent: 34,
                rateLimitsObservedAt: .now
            )
        )

        context.insert(
            StoredAccount(
                identityKey: "account:preview-two",
                name: "Account 2",
                createdAt: .now,
                lastLoginAt: nil,
                customOrder: 1,
                authModeRaw: CodexAuthMode.chatgpt.rawValue,
                emailHint: "preview-two@example.com",
                accountIdentifier: "preview-two",
                sevenDayLimitUsedPercent: nil,
                fiveHourLimitUsedPercent: nil,
                rateLimitsObservedAt: nil
            )
        )

        try? context.save()

        return container
    }
}

actor PreviewAuthFileManager: AuthFileManaging {
    private let previewContents = """
    {
      "auth_mode": "chatgpt",
      "tokens": {
        "account_id": "preview-one",
        "id_token": "eyJhbGciOiJub25lIn0.eyJlbWFpbCI6InByZXZpZXctb25lQGV4YW1wbGUuY29tIiwiaHR0cHM6Ly9hcGkub3BlbmFpLmNvbS9hdXRoIjp7ImNoYXRncHRfYWNjb3VudF9pZCI6InByZXZpZXctb25lIn19.c2ln"
      }
    }
    """

    func linkedLocation() async -> AuthLinkedLocation? {
        AuthLinkedLocation(
            folderURL: URL(fileURLWithPath: "/tmp/.codex", isDirectory: true),
            credentialStoreHint: .file
        )
    }

    func linkLocation(_ selectedURL: URL) async throws -> AuthLinkedLocation {
        AuthLinkedLocation(
            folderURL: selectedURL.deletingLastPathComponent(),
            credentialStoreHint: .file
        )
    }

    func clearLinkedLocation() async {}

    func readAuthFile() async throws -> AuthFileReadResult {
        AuthFileReadResult(
            url: URL(fileURLWithPath: "/tmp/auth.json"),
            contents: previewContents
        )
    }

    func writeAuthFile(_ contents: String) async throws {}

    func startMonitoring(_ onChange: @escaping @Sendable () -> Void) async {}
}

@MainActor
final class PreviewNotificationManager: AccountSwitchNotifying {
    func postSwitchNotification(for accountName: String) async {}
    func requestAuthorizationForNotificationsPreference() async -> NotificationAuthorizationRequestResult { .enabled }
}

actor PreviewSecretStore: AccountSecretStoring {
    func saveSecret(_ contents: String, for accountID: UUID) async throws {}
    func loadSecret(for accountID: UUID) async throws -> String { "{}" }
    func deleteSecret(for accountID: UUID) async throws {}
}

/// Dedicated launch scenarios let UI tests validate edge-case banners and
/// recovery affordances without touching the real sandbox bookmark or Codex
/// auth files on disk.
enum UITestScenario: String {
    case unlinked = "unlinked"
    case missingAuthFile = "missing-auth-file"
    case unsupportedCredentialStore = "unsupported-credential-store"

    static var current: UITestScenario? {
        ProcessInfo.processInfo.environment["CODEX_SWITCHER_UI_TEST_SCENARIO"]
            .flatMap(UITestScenario.init(rawValue:))
    }
}

actor UITestAuthFileManager: AuthFileManaging {
    private let linkedLocationState: AuthLinkedLocation?
    private let contents: String

    init(scenario: UITestScenario) {
        let folderURL = URL(fileURLWithPath: "/tmp/codex-switcher-ui-tests", isDirectory: true)

        switch scenario {
        case .unlinked:
            self.linkedLocationState = nil
            self.contents = ""
        case .missingAuthFile:
            self.linkedLocationState = AuthLinkedLocation(
                folderURL: folderURL,
                credentialStoreHint: .file
            )
            self.contents = ""
        case .unsupportedCredentialStore:
            self.linkedLocationState = AuthLinkedLocation(
                folderURL: folderURL,
                credentialStoreHint: .auto
            )
            self.contents = ""
        }
    }

    func linkedLocation() async -> AuthLinkedLocation? {
        linkedLocationState
    }

    func linkLocation(_ selectedURL: URL) async throws -> AuthLinkedLocation {
        let folderURL = selectedURL.hasDirectoryPath ? selectedURL : selectedURL.deletingLastPathComponent()
        return AuthLinkedLocation(folderURL: folderURL, credentialStoreHint: .file)
    }

    func clearLinkedLocation() async {}

    func readAuthFile() async throws -> AuthFileReadResult {
        guard let linkedLocationState else {
            throw AuthFileAccessError.accessRequired
        }

        switch linkedLocationState.credentialStoreHint {
        case .auto, .keyring:
            throw AuthFileAccessError.unsupportedCredentialStore(
                linkedLocationState.folderURL,
                mode: linkedLocationState.credentialStoreHint
            )
        case .file, .unknown:
            guard !contents.isEmpty else {
                throw AuthFileAccessError.missingAuthFile(
                    linkedLocationState.authFileURL,
                    credentialStoreHint: linkedLocationState.credentialStoreHint
                )
            }

            return AuthFileReadResult(url: linkedLocationState.authFileURL, contents: contents)
        }
    }

    func writeAuthFile(_ contents: String) async throws {}

    func startMonitoring(_ onChange: @escaping @Sendable () -> Void) async {}
}

actor UITestSecretStore: AccountSecretStoring {
    func saveSecret(_ contents: String, for accountID: UUID) async throws {}
    func loadSecret(for accountID: UUID) async throws -> String { "{}" }
    func deleteSecret(for accountID: UUID) async throws {}
}

@MainActor
final class UITestNotificationManager: AccountSwitchNotifying {
    func postSwitchNotification(for accountName: String) async {}
    func requestAuthorizationForNotificationsPreference() async -> NotificationAuthorizationRequestResult { .enabled }
}
