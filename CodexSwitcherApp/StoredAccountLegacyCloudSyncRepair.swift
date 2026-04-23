//
//  StoredAccountLegacyCloudSyncRepair.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-15.
//

import SwiftData

enum StoredAccountLegacyCloudSyncRepair {
    /// `hasLocalSnapshot` used to mirror device-local keychain availability into
    /// the CloudKit-backed account row. That value can legitimately differ per
    /// device, so leaving it in the synced record causes cross-device churn and
    /// can overwrite real metadata edits. Keep the column for schema
    /// compatibility, but normalize old rows back to a shared false value.
    @discardableResult
    static func normalizeLocalOnlyFieldsIfNeeded(in modelContext: ModelContext) throws -> Bool {
        let accounts = try modelContext.fetch(FetchDescriptor<StoredAccount>())
        var didChange = false

        for account in accounts {
            didChange = account.normalizeLegacyLocalOnlyFields() || didChange
        }

        if didChange {
            try modelContext.save()
        }

        return didChange
    }
}
