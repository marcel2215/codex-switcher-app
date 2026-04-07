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
                name: "Unnamed Account 1",
                createdAt: .now.addingTimeInterval(-86_400),
                lastLoginAt: .now.addingTimeInterval(-3_600),
                customOrder: 0,
                authFileContents: "{}",
                authModeRaw: CodexAuthMode.chatgpt.rawValue,
                emailHint: "preview-one@example.com",
                accountIdentifier: "preview-one"
            )
        )

        context.insert(
            StoredAccount(
                identityKey: "account:preview-two",
                name: "Unnamed Account 2",
                createdAt: .now,
                lastLoginAt: nil,
                customOrder: 1,
                authFileContents: "{}",
                authModeRaw: CodexAuthMode.chatgpt.rawValue,
                emailHint: "preview-two@example.com",
                accountIdentifier: "preview-two"
            )
        )

        try? context.save()

        return container
    }
}

@MainActor
final class PreviewAuthFileManager: AuthFileManaging {
    private let previewContents = """
    {
      "auth_mode": "chatgpt",
      "tokens": {
        "account_id": "preview-one",
        "id_token": "eyJhbGciOiJub25lIn0.eyJlbWFpbCI6InByZXZpZXctb25lQGV4YW1wbGUuY29tIiwiaHR0cHM6Ly9hcGkub3BlbmFpLmNvbS9hdXRoIjp7ImNoYXRncHRfYWNjb3VudF9pZCI6InByZXZpZXctb25lIn19.c2ln"
      }
    }
    """

    func readAuthFile(promptIfNeeded: Bool) throws -> AuthFileReadResult {
        AuthFileReadResult(
            url: URL(fileURLWithPath: "/tmp/auth.json"),
            contents: previewContents
        )
    }

    func writeAuthFile(_ contents: String, promptIfNeeded: Bool) throws {}
}

@MainActor
final class PreviewNotificationManager: AccountSwitchNotifying {
    func postSwitchNotification(for accountName: String) async {}
}
