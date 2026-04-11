//
//  IOSCloudSortPreferences.swift
//  Codex Switcher iOS App
//
//  Created by Codex on 2026-04-11.
//

import Foundation
import Observation

@MainActor
@Observable
final class IOSCloudSortPreferences {
    private enum Key {
        static let sortCriterion = "ios.sortCriterion"
        static let sortDirection = "ios.sortDirection"
    }

    @ObservationIgnored private let userDefaults: UserDefaults
    @ObservationIgnored private let cloudStore: NSUbiquitousKeyValueStore
    @ObservationIgnored private var notificationTask: Task<Void, Never>?

    var sortCriterionRawValue: String
    var sortDirectionRawValue: String

    init(
        userDefaults: UserDefaults = .standard,
        cloudStore: NSUbiquitousKeyValueStore = .default
    ) {
        self.userDefaults = userDefaults
        self.cloudStore = cloudStore

        cloudStore.synchronize()
        Self.migrateLocalValuesToCloudIfNeeded(userDefaults: userDefaults, cloudStore: cloudStore)

        sortCriterionRawValue = Self.storedValue(
            forKey: Key.sortCriterion,
            defaultValue: AccountSortCriterion.dateAdded.rawValue,
            userDefaults: userDefaults,
            cloudStore: cloudStore
        )
        sortDirectionRawValue = Self.storedValue(
            forKey: Key.sortDirection,
            defaultValue: SortDirection.ascending.rawValue,
            userDefaults: userDefaults,
            cloudStore: cloudStore
        )

        notificationTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(
                named: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: nil
            ) {
                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    self?.reloadFromCloudStore()
                }
            }
        }
    }

    deinit {
        notificationTask?.cancel()
    }

    func synchronize() {
        cloudStore.synchronize()
        reloadFromCloudStore()
    }

    /// Persist to both local defaults and iCloud key-value storage so the
    /// current device updates immediately while other iOS devices pick it up.
    func persist(sortCriterionRawValue: String, sortDirectionRawValue: String) {
        guard
            self.sortCriterionRawValue != sortCriterionRawValue
                || self.sortDirectionRawValue != sortDirectionRawValue
        else {
            return
        }

        self.sortCriterionRawValue = sortCriterionRawValue
        self.sortDirectionRawValue = sortDirectionRawValue

        userDefaults.set(sortCriterionRawValue, forKey: Key.sortCriterion)
        userDefaults.set(sortDirectionRawValue, forKey: Key.sortDirection)
        cloudStore.set(sortCriterionRawValue, forKey: Key.sortCriterion)
        cloudStore.set(sortDirectionRawValue, forKey: Key.sortDirection)
        cloudStore.synchronize()
    }

    private func reloadFromCloudStore() {
        let resolvedSortCriterionRawValue = Self.storedValue(
            forKey: Key.sortCriterion,
            defaultValue: AccountSortCriterion.dateAdded.rawValue,
            userDefaults: userDefaults,
            cloudStore: cloudStore
        )
        let resolvedSortDirectionRawValue = Self.storedValue(
            forKey: Key.sortDirection,
            defaultValue: SortDirection.ascending.rawValue,
            userDefaults: userDefaults,
            cloudStore: cloudStore
        )

        if sortCriterionRawValue != resolvedSortCriterionRawValue {
            sortCriterionRawValue = resolvedSortCriterionRawValue
        }

        if sortDirectionRawValue != resolvedSortDirectionRawValue {
            sortDirectionRawValue = resolvedSortDirectionRawValue
        }
    }

    private static func migrateLocalValuesToCloudIfNeeded(
        userDefaults: UserDefaults,
        cloudStore: NSUbiquitousKeyValueStore
    ) {
        if cloudStore.object(forKey: Key.sortCriterion) == nil,
           let localSortCriterion = userDefaults.string(forKey: Key.sortCriterion),
           !localSortCriterion.isEmpty {
            cloudStore.set(localSortCriterion, forKey: Key.sortCriterion)
        }

        if cloudStore.object(forKey: Key.sortDirection) == nil,
           let localSortDirection = userDefaults.string(forKey: Key.sortDirection),
           !localSortDirection.isEmpty {
            cloudStore.set(localSortDirection, forKey: Key.sortDirection)
        }
    }

    private static func storedValue(
        forKey key: String,
        defaultValue: String,
        userDefaults: UserDefaults,
        cloudStore: NSUbiquitousKeyValueStore
    ) -> String {
        if let cloudValue = cloudStore.string(forKey: key), !cloudValue.isEmpty {
            return cloudValue
        }

        if let localValue = userDefaults.string(forKey: key), !localValue.isEmpty {
            return localValue
        }

        return defaultValue
    }
}
