//
//  AccountsPresentationLogic.swift
//  Codex Switcher
//
//  Created by Marcel Kwiatkowski on 2026-04-11.
//

import Foundation

enum AccountsPresentationLogic {
    private nonisolated static let unavailableSuffix = " (Unavailable)"
    typealias AccountListDisplayNameParts = (name: String, unavailableSuffix: String?)

    nonisolated static func normalizedSearchText(_ searchText: String) -> String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func displayName(for account: StoredAccount) -> String {
        displayName(
            name: account.name,
            emailHint: account.emailHint,
            accountIdentifier: account.accountIdentifier,
            identityKey: account.identityKey
        )
    }

    nonisolated static func displayName(
        name: String,
        emailHint: String?,
        accountIdentifier: String?,
        identityKey: String
    ) -> String {
        normalizedDisplayText(name)
            ?? normalizedDisplayText(emailHint)
            ?? normalizedDisplayText(accountIdentifier)
            ?? normalizedDisplayText(identityKey)
            ?? "Unnamed Account"
    }

    nonisolated static func accountListDisplayName(for account: StoredAccount) -> String {
        let resolvedName = displayName(for: account)
        guard account.isUnavailable else {
            return resolvedName
        }

        guard !resolvedName.hasSuffix(unavailableSuffix) else {
            return resolvedName
        }

        return "\(resolvedName)\(unavailableSuffix)"
    }

    nonisolated static func accountListDisplayNameParts(
        for account: StoredAccount
    ) -> AccountListDisplayNameParts {
        let resolvedName = displayName(for: account)
        let unavailableSuffixToDisplay: String? = if account.isUnavailable {
            resolvedName.hasSuffix(unavailableSuffix) ? nil : unavailableSuffix
        } else {
            nil
        }

        return (resolvedName, unavailableSuffixToDisplay)
    }

    nonisolated static func normalizedSortDirection(
        for sortCriterion: AccountSortCriterion,
        requestedDirection: SortDirection
    ) -> SortDirection {
        sortCriterion == .custom ? .ascending : requestedDirection
    }

    nonisolated static func canEditCustomOrder(
        searchText: String,
        sortCriterion: AccountSortCriterion,
        sortDirection: SortDirection
    ) -> Bool {
        sortCriterion == .custom
            && normalizedSortDirection(for: sortCriterion, requestedDirection: sortDirection) == .ascending
            && normalizedSearchText(searchText).isEmpty
    }

    nonisolated static func normalizedRenamedAccountName(_ proposedName: String) -> String? {
        let trimmedName = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? nil : trimmedName
    }

    nonisolated static func displayedAccounts(
        from accounts: [StoredAccount],
        searchText: String,
        sortCriterion: AccountSortCriterion,
        sortDirection: SortDirection
    ) -> [StoredAccount] {
        let trimmedSearch = normalizedSearchText(searchText)
        let filteredAccounts: [StoredAccount]

        if trimmedSearch.isEmpty {
            filteredAccounts = accounts
        } else {
            let lowercasedSearch = trimmedSearch.lowercased()
            filteredAccounts = accounts.filter { account in
                account.name.lowercased().contains(lowercasedSearch)
                    || (account.emailHint?.lowercased().contains(lowercasedSearch) ?? false)
                    || (account.accountIdentifier?.lowercased().contains(lowercasedSearch) ?? false)
            }
        }

        return sortedAccounts(
            from: filteredAccounts,
            sortCriterion: sortCriterion,
            sortDirection: sortDirection
        )
    }

    nonisolated static func sortedAccounts(
        from accounts: [StoredAccount],
        sortCriterion: AccountSortCriterion,
        sortDirection: SortDirection
    ) -> [StoredAccount] {
        let resolvedDirection = normalizedSortDirection(
            for: sortCriterion,
            requestedDirection: sortDirection
        )

        return accounts.sorted { lhs, rhs in
            if let pinnedFirst = pinnedAccountsComeBefore(
                lhsIsPinned: lhs.isPinned,
                rhsIsPinned: rhs.isPinned
            ) {
                return pinnedFirst
            }

            if sortCriterion == .rateLimit {
                if areEquivalentForRateLimitSort(lhs, rhs) {
                    return lhs.createdAt < rhs.createdAt
                }

                return rateLimitSortComesBefore(lhs, rhs, direction: resolvedDirection)
            }

            let orderedAscending: Bool = switch sortCriterion {
            case .name:
                displayName(for: lhs).localizedCaseInsensitiveCompare(displayName(for: rhs)) == .orderedAscending
            case .dateAdded:
                lhs.createdAt < rhs.createdAt
            case .lastLogin:
                (lhs.lastLoginAt ?? .distantPast) < (rhs.lastLoginAt ?? .distantPast)
            case .rateLimit:
                false
            case .custom:
                lhs.customOrder < rhs.customOrder
            }

            let orderedDescending: Bool = switch sortCriterion {
            case .name:
                displayName(for: lhs).localizedCaseInsensitiveCompare(displayName(for: rhs)) == .orderedDescending
            case .dateAdded:
                lhs.createdAt > rhs.createdAt
            case .lastLogin:
                (lhs.lastLoginAt ?? .distantPast) > (rhs.lastLoginAt ?? .distantPast)
            case .rateLimit:
                false
            case .custom:
                lhs.customOrder > rhs.customOrder
            }

            if isEquivalent(lhs, rhs, for: sortCriterion) {
                return lhs.createdAt < rhs.createdAt
            }

            return resolvedDirection == .ascending ? orderedAscending : orderedDescending
        }
    }

    /// Pinned and unpinned accounts form separate custom-order lanes. Keep the
    /// visible order within each lane while preserving the invariant that every
    /// pinned account stays above every unpinned account after the save.
    nonisolated static func customOrderPersistenceSequence(
        for reorderedAccounts: [StoredAccount]
    ) -> [StoredAccount] {
        reorderedAccounts.filter(\.isPinned) + reorderedAccounts.filter { !$0.isPinned }
    }

    nonisolated static func storedAccountCustomOrderComparator(
        lhs: StoredAccount,
        rhs: StoredAccount
    ) -> Bool {
        if let pinnedFirst = pinnedAccountsComeBefore(
            lhsIsPinned: lhs.isPinned,
            rhsIsPinned: rhs.isPinned
        ) {
            return pinnedFirst
        }

        if lhs.customOrder != rhs.customOrder {
            return lhs.customOrder < rhs.customOrder
        }

        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }

        return lhs.id.uuidString < rhs.id.uuidString
    }

    nonisolated static func sharedAccountRecordComparator(
        lhs: SharedCodexAccountRecord,
        rhs: SharedCodexAccountRecord
    ) -> Bool {
        if let pinnedFirst = pinnedAccountsComeBefore(
            lhsIsPinned: lhs.isPinned,
            rhsIsPinned: rhs.isPinned
        ) {
            return pinnedFirst
        }

        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }

        return displayName(
            name: lhs.name,
            emailHint: lhs.emailHint,
            accountIdentifier: lhs.accountIdentifier,
            identityKey: lhs.id
        )
        .localizedStandardCompare(
            displayName(
                name: rhs.name,
                emailHint: rhs.emailHint,
                accountIdentifier: rhs.accountIdentifier,
                identityKey: rhs.id
            )
        ) == .orderedAscending
    }

    private nonisolated static func isEquivalent(
        _ lhs: StoredAccount,
        _ rhs: StoredAccount,
        for criterion: AccountSortCriterion
    ) -> Bool {
        switch criterion {
        case .name:
            displayName(for: lhs).localizedCaseInsensitiveCompare(displayName(for: rhs)) == .orderedSame
        case .dateAdded:
            lhs.createdAt == rhs.createdAt
        case .lastLogin:
            lhs.lastLoginAt == rhs.lastLoginAt
        case .rateLimit:
            false
        case .custom:
            lhs.customOrder == rhs.customOrder
        }
    }

    private nonisolated static func rateLimitSortComesBefore(
        _ lhs: StoredAccount,
        _ rhs: StoredAccount,
        direction: SortDirection
    ) -> Bool {
        let lhsMetrics = rateLimitSortMetrics(for: lhs)
        let rhsMetrics = rateLimitSortMetrics(for: rhs)

        if lhsMetrics.isComplete != rhsMetrics.isComplete {
            return lhsMetrics.isComplete
        }

        if lhsMetrics.primary != rhsMetrics.primary {
            return direction == .ascending
                ? lhsMetrics.primary < rhsMetrics.primary
                : lhsMetrics.primary > rhsMetrics.primary
        }

        if lhsMetrics.secondary != rhsMetrics.secondary {
            return direction == .ascending
                ? lhsMetrics.secondary < rhsMetrics.secondary
                : lhsMetrics.secondary > rhsMetrics.secondary
        }

        return lhs.createdAt < rhs.createdAt
    }

    private nonisolated static func areEquivalentForRateLimitSort(
        _ lhs: StoredAccount,
        _ rhs: StoredAccount
    ) -> Bool {
        let lhsMetrics = rateLimitSortMetrics(for: lhs)
        let rhsMetrics = rateLimitSortMetrics(for: rhs)
        return lhsMetrics.isComplete == rhsMetrics.isComplete
            && lhsMetrics.primary == rhsMetrics.primary
            && lhsMetrics.secondary == rhsMetrics.secondary
    }

    private nonisolated static func rateLimitSortMetrics(
        for account: StoredAccount
    ) -> (isComplete: Bool, primary: Int, secondary: Int) {
        let normalizedValues = normalizedRateLimitSortValues(for: account)
        return (
            normalizedValues.isComplete,
            normalizedValues.values.min() ?? 0,
            normalizedValues.values.max() ?? 0
        )
    }

    private nonisolated static func normalizedRateLimitSortValues(
        for account: StoredAccount
    ) -> (isComplete: Bool, values: [Int]) {
        if account.isUnavailable {
            return (true, [0, 0])
        }

        guard let fiveHourRemainingPercent = account.fiveHourLimitUsedPercent,
              let sevenDayRemainingPercent = account.sevenDayLimitUsedPercent else {
            return (false, [0, 0])
        }

        return (
            true,
            [fiveHourRemainingPercent, sevenDayRemainingPercent]
                .map { min(max($0, 0), 100) }
        )
    }

    private nonisolated static func pinnedAccountsComeBefore(
        lhsIsPinned: Bool,
        rhsIsPinned: Bool
    ) -> Bool? {
        guard lhsIsPinned != rhsIsPinned else {
            return nil
        }

        return lhsIsPinned && !rhsIsPinned
    }

    private nonisolated static func normalizedDisplayText(_ text: String?) -> String? {
        guard let text else {
            return nil
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedText.isEmpty ? nil : trimmedText
    }
}
