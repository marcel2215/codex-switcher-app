//
//  AppController.swift
//  Codex Switcher Mac App
//
//  Created by Marcel Kwiatkowski on 2026-04-08.
//

import AppKit
import AppIntents
import Foundation
import IOKit.ps
import ObjectiveC.runtime
import Observation
import OSLog
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct UserFacingAlert: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
}

struct UnavailableAccountRecoveryPrompt: Identifiable, Equatable {
    let id = UUID()
    let accountID: UUID
    let accountName: String
    let reason: StoredAccountUnavailableReason?
}

struct PendingCodexRestartBanner: Identifiable, Equatable {
    enum Target: Equatable {
        case account(name: String)
        case none

        var displayName: String {
            switch self {
            case let .account(name):
                name
            case .none:
                "None"
            }
        }
    }

    let id = UUID()
    let target: Target
    let shownAt: Date
    let codexProcessIDsAtSwitch: Set<pid_t>
}

#if os(macOS)
struct AccountArchiveSharingServiceOption: Identifiable {
    let id: String
    let title: String
    let image: NSImage

    fileprivate let service: NSSharingService
}
#endif

@Observable
@MainActor
final class AppController {
    nonisolated static let noneAccountSelectionID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    private nonisolated static let batterySaverRefreshPauseThreshold = 15
    private nonisolated static let currentAccountRateLimitRefreshInterval: TimeInterval = 60
    private nonisolated static let visibleAccountRateLimitRefreshInterval: TimeInterval = 5 * 60
    private nonisolated static let rateLimitPollingCadence: Duration = .seconds(5)
    private nonisolated static let initialRateLimitFailureBackoff: TimeInterval = 60
    private nonisolated static let maximumRateLimitFailureBackoff: TimeInterval = 15 * 60
    private nonisolated static let autopilotLoopCadence: Duration = .seconds(20)
    private nonisolated static let autopilotRefreshInterval: TimeInterval = 5 * 60
    private nonisolated static let autopilotSessionQuietWindow: TimeInterval = 45
    private nonisolated static let autopilotTaskTriggeredMinimumGap: TimeInterval = 90
    private nonisolated static let autopilotWakeDelay: TimeInterval = 0

    var selection: Set<UUID> = [] {
        didSet {
            guard selection != oldValue else {
                return
            }

            publishSharedState(immediate: true)
        }
    }
    var searchText = ""
    var sortCriterion: AccountSortCriterion = .dateAdded {
        didSet {
            let normalizedDirection = AccountsPresentationLogic.normalizedSortDirection(
                for: sortCriterion,
                requestedDirection: sortDirection
            )

            if sortDirection != normalizedDirection {
                sortDirection = normalizedDirection
            }
        }
    }
    var sortDirection: SortDirection = .ascending {
        didSet {
            let normalizedDirection = AccountsPresentationLogic.normalizedSortDirection(
                for: sortCriterion,
                requestedDirection: sortDirection
            )

            if sortDirection != normalizedDirection {
                sortDirection = normalizedDirection
            }
        }
    }
    var renameTargetID: UUID?
    var presentedAlert: UserFacingAlert?
    var unavailableAccountRecoveryPrompt: UnavailableAccountRecoveryPrompt?
    private(set) var pendingCodexRestartBanner: PendingCodexRestartBanner?
    var isShowingLocationPicker = false
    var isShowingAccountArchiveImporter = false
    private(set) var activeIdentityKey: String?
    private(set) var authAccessState: AuthAccessState = .unlinked
    private(set) var isSwitching = false
    private(set) var isCapturingCurrentAccount = false

    @ObservationIgnored private let authFileManager: AuthFileManaging
    @ObservationIgnored private let secretStore: AccountSnapshotStoring
    @ObservationIgnored private let snapshotAvailabilityStore: LocalAccountSnapshotAvailabilityStore
    @ObservationIgnored private let syncedRateLimitCredentialStore: SyncedRateLimitCredentialStoring
    @ObservationIgnored private let notificationManager: AccountSwitchNotifying
    @ObservationIgnored private let rateLimitProvider: CodexRateLimitProviding
    @ObservationIgnored private let sessionRateLimitReader: CodexSessionRateLimitReader
    @ObservationIgnored private let officialLoginCoordinator: CodexOfficialLoginCoordinating
    @ObservationIgnored private let locationPicker: CodexFolderLocationPicking
    @ObservationIgnored private let codexDesktopAppObserver: CodexDesktopAppObserver
    @ObservationIgnored private let lowPowerModeProvider: () -> Bool
    @ObservationIgnored private let batteryChargePercentProvider: () -> Int?
    @ObservationIgnored private let terminateApplication: () -> Void
    @ObservationIgnored private let archiveExporter: CodexAccountArchiveFileExporter
    @ObservationIgnored private let logger: Logger
    @ObservationIgnored private let startupAlert: UserFacingAlert?

    @ObservationIgnored private var modelContainer: ModelContainer?
    @ObservationIgnored private var remoteDeletionCleanup: RemoteAccountDeletionCleanup?
    @ObservationIgnored private var hasConfiguredInitialState = false
    @ObservationIgnored private var hasStartedMonitoring = false
    @ObservationIgnored private var hasStartedObservingSystemState = false
    @ObservationIgnored private var pendingLocationAction: PendingLocationAction?
    @ObservationIgnored private var initializationTask: Task<Void, Never>?
    @ObservationIgnored private var captureTask: Task<Void, Never>?
    @ObservationIgnored private var switchTask: Task<Void, Never>?
    @ObservationIgnored private var activeSwitchOperationID: UUID?
    @ObservationIgnored nonisolated(unsafe) private var remoteSwitchObserver: NSObjectProtocol?
    @ObservationIgnored nonisolated(unsafe) private var sharedCommandObserver: NSObjectProtocol?
    @ObservationIgnored nonisolated(unsafe) private var pendingAccountOpenObserver: NSObjectProtocol?
    @ObservationIgnored nonisolated(unsafe) private var workspaceLaunchObserver: NSObjectProtocol?
    @ObservationIgnored nonisolated(unsafe) private var workspaceTerminationObserver: NSObjectProtocol?
    @ObservationIgnored private var systemStateObservationTasks: [Task<Void, Never>] = []
    @ObservationIgnored private var sharedStatePublishTask: Task<Void, Never>?
    @ObservationIgnored private var observedAuthFileChangeTask: Task<Void, Never>?
    @ObservationIgnored private var rateLimitPollingTask: Task<Void, Never>?
    @ObservationIgnored private var autopilotTask: Task<Void, Never>?
    @ObservationIgnored private var rateLimitSnapshotsByIdentityKey: [String: CodexRateLimitSnapshot] = [:]
    @ObservationIgnored private var visibleRateLimitIdentityCounts: [String: Int] = [:]
    @ObservationIgnored private var pendingForcedRateLimitRefreshes: Set<String> = []
    @ObservationIgnored private var rateLimitRefreshesInFlight: Set<String> = []
    @ObservationIgnored private var rateLimitFailureBackoffUntil: [String: Date] = [:]
    @ObservationIgnored private var rateLimitFailureBackoffDurations: [String: TimeInterval] = [:]
    @ObservationIgnored private var isApplicationActive = false
    @ObservationIgnored private var isMenuBarPresented = false
    @ObservationIgnored private var isAutopilotEnabled = false
    @ObservationIgnored private var isPrimarySelectionContextPresented = false
    @ObservationIgnored private var isSystemSleeping = false
    @ObservationIgnored private var areScreensSleeping = false
    @ObservationIgnored private var nextAutopilotEvaluationAt: Date?
    @ObservationIgnored private var pendingAutopilotImmediateTrigger: AutopilotTrigger?
    @ObservationIgnored private var lastAutopilotEvaluationAt: Date?
    @ObservationIgnored private var lastObservedSessionActivityAt: Date?
    @ObservationIgnored private var lastHandledSessionActivityAt: Date?
    @ObservationIgnored private var isProcessingSharedCommands = false
    @ObservationIgnored private var shouldProcessSharedCommandsAgain = false

    init(
        authFileManager: AuthFileManaging,
        secretStore: AccountSnapshotStoring,
        snapshotAvailabilityStore: LocalAccountSnapshotAvailabilityStore = LocalAccountSnapshotAvailabilityStore(),
        syncedRateLimitCredentialStore: SyncedRateLimitCredentialStoring = SyncedRateLimitCredentialStore(),
        notificationManager: AccountSwitchNotifying,
        rateLimitProvider: CodexRateLimitProviding = CodexRateLimitProvider(),
        sessionRateLimitReader: CodexSessionRateLimitReader = CodexSessionRateLimitReader(),
        officialLoginCoordinator: CodexOfficialLoginCoordinating = CodexOfficialLoginCoordinator(),
        locationPicker: CodexFolderLocationPicking = CodexFolderLocationPicker(),
        codexDesktopAppObserver: CodexDesktopAppObserver = CodexDesktopAppObserver(),
        startupAlert: UserFacingAlert? = nil,
        modelContainer: ModelContainer? = nil,
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "CodexSwitcher",
        lowPowerModeProvider: @escaping () -> Bool = AppController.defaultLowPowerModeProvider,
        batteryChargePercentProvider: @escaping () -> Int? = AppController.defaultBatteryChargePercentProvider,
        terminateApplication: @escaping () -> Void = { NSApp.terminate(nil) },
        archiveExporter: CodexAccountArchiveFileExporter = CodexAccountArchiveFileExporter(
            syncedRateLimitCredentialStore: SyncedRateLimitCredentialStore()
        ),
        autopilotEnabled: Bool = false
    ) {
        self.authFileManager = authFileManager
        self.secretStore = secretStore
        self.snapshotAvailabilityStore = snapshotAvailabilityStore
        self.syncedRateLimitCredentialStore = syncedRateLimitCredentialStore
        self.notificationManager = notificationManager
        self.rateLimitProvider = rateLimitProvider
        self.sessionRateLimitReader = sessionRateLimitReader
        self.officialLoginCoordinator = officialLoginCoordinator
        self.locationPicker = locationPicker
        self.codexDesktopAppObserver = codexDesktopAppObserver
        self.lowPowerModeProvider = lowPowerModeProvider
        self.batteryChargePercentProvider = batteryChargePercentProvider
        self.terminateApplication = terminateApplication
        self.archiveExporter = archiveExporter
        self.startupAlert = startupAlert
        self.modelContainer = modelContainer
        self.isAutopilotEnabled = autopilotEnabled
        self.logger = Logger(subsystem: bundleIdentifier, category: "AppController")
        if let modelContainer {
            self.remoteDeletionCleanup = RemoteAccountDeletionCleanup(
                modelContainer: modelContainer,
                secretStore: secretStore,
                syncedRateLimitCredentialStore: syncedRateLimitCredentialStore,
                logger: Logger(subsystem: bundleIdentifier, category: "RemoteDeletionCleanup")
            )
        }
    }

    deinit {
        initializationTask?.cancel()
        captureTask?.cancel()
        switchTask?.cancel()
        sharedStatePublishTask?.cancel()
        rateLimitPollingTask?.cancel()
        autopilotTask?.cancel()
        observedAuthFileChangeTask?.cancel()
        if let remoteSwitchObserver {
            DistributedNotificationCenter.default().removeObserver(remoteSwitchObserver)
        }
        if let sharedCommandObserver {
            DistributedNotificationCenter.default().removeObserver(sharedCommandObserver)
        }
        if let pendingAccountOpenObserver {
            DistributedNotificationCenter.default().removeObserver(pendingAccountOpenObserver)
        }
        if let workspaceLaunchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceLaunchObserver)
        }
        if let workspaceTerminationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceTerminationObserver)
        }
        systemStateObservationTasks.forEach { $0.cancel() }
    }

    func configure(modelContext: ModelContext, undoManager: UndoManager?) {
        // Scene environment contexts can be recreated as windows and menu-bar
        // scenes appear or disappear. Persist the owning container instead of
        // holding onto a scene-scoped ModelContext reference that may no longer
        // be valid when an async refresh fires later.
        if modelContainer == nil {
            modelContainer = modelContext.container
        }

        if remoteDeletionCleanup == nil, let modelContainer {
            remoteDeletionCleanup = RemoteAccountDeletionCleanup(
                modelContainer: modelContainer,
                secretStore: secretStore,
                syncedRateLimitCredentialStore: syncedRateLimitCredentialStore,
                logger: Logger(
                    subsystem: Bundle.main.bundleIdentifier ?? "CodexSwitcher",
                    category: "RemoteDeletionCleanup"
                )
            )
        }

        let resolvedModelContext = modelContainer?.mainContext ?? modelContext
        if let undoManager {
            resolvedModelContext.undoManager = undoManager
        }

        guard !hasConfiguredInitialState else {
            return
        }

        hasConfiguredInitialState = true
        startObservingRemoteSwitchesIfNeeded()
        if !Self.isRunningMainApplicationUnitTests {
            startObservingSharedCommandsIfNeeded()
            startObservingPendingAccountOpenRequestsIfNeeded()
        }
        startObservingSystemStateIfNeeded()

        if let startupAlert {
            presentedAlert = startupAlert
        }

        let initializationTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            await self.reconcileStoredSnapshotsIfNeeded()
            self.reconcileSharedLastLoginUpdatesIfNeeded()
            await self.refreshAuthState(showUnexpectedErrors: false)
            self.reconcileDisplayOnlyFieldsIfNeeded()
            await self.remoteDeletionCleanup?.consumeHistoryIfNeeded()
            if !Self.isRunningMainApplicationUnitTests {
                self.publishSharedState()
            }
            self.initializationTask = nil
            if !Self.isRunningMainApplicationUnitTests {
                await self.processPendingSharedCommands()
            }
        }
        self.initializationTask = initializationTask

        startMonitoringIfNeeded()
        // Autopilot startup checks can now fire immediately, so make sure the
        // initialization task exists before the loop can begin awaiting it.
        updateAutopilotState()
    }

    var canEditCustomOrder: Bool {
        AccountsPresentationLogic.canEditCustomOrder(
            searchText: searchText,
            sortCriterion: sortCriterion,
            sortDirection: sortDirection
        )
    }

    var selectedAccountID: UUID? {
        guard selection.count == 1 else {
            return nil
        }

        let selectedID = selection.first
        return selectedID == Self.noneAccountSelectionID ? nil : selectedID
    }

    var selectedAccountIconOption: AccountIconOption? {
        guard
            let selectedAccountID,
            let account = try? account(withID: selectedAccountID)
        else {
            return nil
        }

        return AccountIconOption.resolve(from: account.iconSystemName)
    }

    var selectedAccountIsPinned: Bool? {
        guard
            let selectedAccountID,
            let account = try? account(withID: selectedAccountID)
        else {
            return nil
        }

        return account.isPinned
    }

    private var copyableSelectedAccountIDs: Set<UUID> {
        Set(selection.filter { $0 != Self.noneAccountSelectionID })
    }

#if os(macOS)
    var selectedAccountIDsForMenuActions: Set<UUID> {
        copyableSelectedAccountIDs
    }
#endif

    var shouldShowAuthStatusBanner: Bool {
        authAccessState.showsInlineStatus
    }

    var canCaptureCurrentAccount: Bool {
        !isCapturingCurrentAccount && !isSwitching
    }

    var captureCurrentAccountHelpText: String {
        if isCapturingCurrentAccount {
            return "Adding the current account..."
        }

        if isSwitching {
            return "Wait for the current account switch to finish."
        }

        switch authAccessState {
        case .ready:
            return "Add the current Codex auth.json account, or sign in through Codex if it is already saved."
        case .unlinked:
            return "Sign in through Codex, or link the Codex folder to capture the current auth.json first."
        case .missingAuthFile:
            return "Sign in through Codex to add an account."
        case .locationUnavailable:
            return "Relink the Codex folder or sign in through Codex to add an account."
        case .accessDenied:
            return "Grant folder access or sign in through Codex to add an account."
        case .corruptAuthFile:
            return "Sign in through Codex, or fix the linked auth.json and try again."
        case .unsupportedCredentialStore:
            return "Sign in through Codex to add an isolated file-backed account snapshot."
        }
    }

    var linkedFolderPath: String? {
        authAccessState.linkedFolderURL?.path
    }

    var settingsLinkButtonTitle: String {
        "Select"
    }

    var hasSavedAccounts: Bool {
        ((try? !fetchAccounts().isEmpty) == true)
    }

    func archiveTransferItem(for account: StoredAccount) -> CodexAccountArchiveTransferItem {
        archiveTransferItem(for: [account])
    }

    func archiveTransferItem(for accounts: [StoredAccount]) -> CodexAccountArchiveTransferItem {
        let orderedAccounts = uniqueAccountsPreservingDisplayOrder(accounts)
        let requests = orderedAccounts.map { account in
            CodexAccountArchiveExportRequest(
                account: account,
                hasLocalSnapshot: hasLocalSnapshot(for: account)
            )
        }

        return CodexAccountArchiveTransferItem(
            id: orderedAccounts.first?.id ?? UUID(),
            requests: requests,
            reorderToken: orderedAccounts.map(\.id.uuidString).joined(separator: "\n"),
            exporter: archiveExporter
        )
    }

    func prepareArchiveFile(for account: StoredAccount) async throws -> PreparedCodexAccountArchiveFile {
        let transferItem = archiveTransferItem(for: account)
        let fileURL = try await archiveExporter.exportFile(for: transferItem.request)
        return PreparedCodexAccountArchiveFile(
            fileURL: fileURL,
            suggestedFilename: transferItem.exportedArchiveFilename
        )
    }

#if os(macOS)
    func macOSDragItemProvider(
        for accounts: [StoredAccount],
        includeReorderToken: Bool
    ) -> NSItemProvider {
        let orderedAccounts = uniqueAccountsPreservingDisplayOrder(accounts)
        let transferItem = archiveTransferItem(for: orderedAccounts)

        guard orderedAccounts.allSatisfy({ hasLocalSnapshot(for: $0) }) else {
            let provider = NSItemProvider()

            if includeReorderToken, !transferItem.reorderToken.isEmpty {
                provider.registerDataRepresentation(
                    forTypeIdentifier: UTType.plainText.identifier,
                    visibility: .ownProcess
                ) { completion in
                    completion(Data(transferItem.reorderToken.utf8), nil)
                    return nil
                }
            }

            return provider
        }

        return transferItem.macOSItemProvider(includeReorderToken: includeReorderToken)
    }

    func copySelectedAccountsToPasteboard() {
        if Self.forwardPasteboardCommandToTextInput(#selector(NSText.copy(_:))) {
            return
        }

        copyAccountsToPasteboard(withIDs: copyableSelectedAccountIDs)
    }

    func copyAccountsToPasteboard(withIDs accountIDs: Set<UUID>) {
        guard renameTargetID == nil else {
            return
        }

        let accountIDs = Set(accountIDs.filter { $0 != Self.noneAccountSelectionID })
        guard !accountIDs.isEmpty else {
            return
        }

        Task { [weak self] in
            guard let self else {
                return
            }

            await self.copyAccountArchivesToPasteboard(withIDs: accountIDs)
        }
    }

    var canPasteAccountArchivesFromPasteboard: Bool {
        !Self.accountArchiveURLs(from: .general).isEmpty
    }

    func pasteAccountArchivesFromPasteboard() {
        if Self.forwardPasteboardCommandToTextInput(#selector(NSText.paste(_:))) {
            return
        }

        pasteAccountArchivesFromGeneralPasteboard()
    }

    func pasteAccountArchivesFromContextMenu() {
        pasteAccountArchivesFromGeneralPasteboard()
    }

    private func pasteAccountArchivesFromGeneralPasteboard() {
        guard renameTargetID == nil else {
            return
        }

        let accountArchiveURLs = Self.accountArchiveURLs(from: .general)
        guard !accountArchiveURLs.isEmpty else {
            return
        }

        Task { [weak self] in
            guard let self else {
                return
            }

            await self.importAccountArchives(from: accountArchiveURLs)
        }
    }

    func accountArchiveSharingServiceOptions() -> [AccountArchiveSharingServiceOption] {
        let previewURL = Self.accountArchiveSharingPreviewURL()
        return Self.inlineAccountArchiveSharingServices(for: [previewURL])
            .enumerated()
            .map { index, service in
                let menuTitle = service.menuItemTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                let title = menuTitle.isEmpty ? service.title : menuTitle
                return AccountArchiveSharingServiceOption(
                    id: "\(index)-\(title)-\(service.title)",
                    title: title,
                    image: service.image,
                    service: service
                )
            }
    }

    func shareAccounts(withIDs accountIDs: Set<UUID>, using option: AccountArchiveSharingServiceOption) {
        guard renameTargetID == nil else {
            return
        }

        let accountIDs = Set(accountIDs.filter { $0 != Self.noneAccountSelectionID })
        guard !accountIDs.isEmpty else {
            return
        }

        Task { [weak self] in
            guard let self else {
                return
            }

            await self.shareAccountArchives(withIDs: accountIDs, using: option.service)
        }
    }

    private func copyAccountArchivesToPasteboard(withIDs accountIDs: Set<UUID>) async {
        await waitForInitializationIfNeeded()

        do {
            let orderedAccounts = sortedAccounts(from: try fetchAccounts())
                .filter { accountIDs.contains($0.id) }
            guard !orderedAccounts.isEmpty else {
                return
            }

            let transferItem = archiveTransferItem(for: orderedAccounts)
            guard await transferItem.canExport() else {
                throw ControllerError.accountNeedsLocalSnapshotForExport
            }

            let fileURL = try await archiveExporter.exportFile(for: transferItem.request)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            guard pasteboard.writeObjects([fileURL as NSURL]) else {
                throw ControllerError.pasteboardWriteFailed
            }
        } catch {
            present(error, title: "Couldn't Copy Account")
        }
    }

    private func shareAccountArchives(
        withIDs accountIDs: Set<UUID>,
        using service: NSSharingService
    ) async {
        await waitForInitializationIfNeeded()

        do {
            let orderedAccounts = sortedAccounts(from: try fetchAccounts())
                .filter { accountIDs.contains($0.id) }
            guard !orderedAccounts.isEmpty else {
                return
            }

            let transferItem = archiveTransferItem(for: orderedAccounts)
            guard await transferItem.canExport() else {
                throw ControllerError.accountNeedsLocalSnapshotForExport
            }

            let fileURL = try await archiveExporter.exportFile(for: transferItem.request)
            service.subject = transferItem.exportedArchiveFilename
            service.perform(withItems: [fileURL])
        } catch {
            present(error, title: "Couldn't Share Account")
        }
    }

    private static func accountArchiveURLs(from pasteboard: NSPasteboard) -> [URL] {
        let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) ?? []
        var seenURLs = Set<URL>()

        return objects.compactMap { object in
            guard let url = object as? URL ?? (object as? NSURL).map({ $0 as URL }),
                  isAccountArchiveURL(url),
                  seenURLs.insert(url).inserted
            else {
                return nil
            }

            return url
        }
    }

    private static func inlineAccountArchiveSharingServices(for items: [Any]) -> [NSSharingService] {
        let selector = NSSelectorFromString("sharingServicesForItems:")
        guard let method = class_getClassMethod(NSSharingService.self, selector) else {
            return []
        }

        typealias SharingServicesFunction = @convention(c) (AnyClass, Selector, NSArray) -> NSArray
        let implementation = method_getImplementation(method)
        let function = unsafeBitCast(implementation, to: SharingServicesFunction.self)
        return function(NSSharingService.self, selector, items as NSArray) as? [NSSharingService] ?? []
    }

    private static func forwardPasteboardCommandToTextInput(_ action: Selector) -> Bool {
        guard NSApp.keyWindow?.firstResponder is NSTextView else {
            return false
        }

        return NSApp.sendAction(action, to: nil, from: nil)
    }

    private static func accountArchiveSharingPreviewURL() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Codex Account.cxa", isDirectory: false)

        if !FileManager.default.fileExists(atPath: url.path) {
            try? Data().write(to: url, options: .atomic)
        }

        return url
    }
#endif

    private func hasLocalSnapshot(for account: StoredAccount) -> Bool {
        snapshotAvailabilityStore.containsSnapshot(forIdentityKey: account.identityKey)
    }

    // Sort preferences are persisted by the SwiftUI app layer with AppStorage.
    // Restore them here so unknown raw values degrade to safe defaults instead
    // of leaving the controller in an invalid state.
    func restoreSortPreferences(
        sortCriterionRawValue: String,
        sortDirectionRawValue: String
    ) {
        let resolvedCriterion = AccountSortCriterion(rawValue: sortCriterionRawValue) ?? .dateAdded
        let resolvedDirection = AccountsPresentationLogic.normalizedSortDirection(
            for: resolvedCriterion,
            requestedDirection: SortDirection(rawValue: sortDirectionRawValue) ?? .ascending
        )

        if sortCriterion != resolvedCriterion {
            sortCriterion = resolvedCriterion
        }

        if sortDirection != resolvedDirection {
            sortDirection = resolvedDirection
        }
    }

    /// Settings owns the user preference, but the controller forwards the
    /// explicit enable action to the notification service so the permission
    /// prompt stays centralized and testable.
    func requestNotificationAuthorizationForSettings() async -> NotificationAuthorizationRequestResult {
        await notificationManager.requestAuthorizationForNotificationsPreference()
    }

    func setAutopilotEnabled(_ isEnabled: Bool) {
        guard isAutopilotEnabled != isEnabled else {
            return
        }

        isAutopilotEnabled = isEnabled

        if isEnabled {
            // Ignore session activity that predates the user's opt-in, then
            // immediately reevaluate using fresh remote limits.
            lastHandledSessionActivityAt = lastObservedSessionActivityAt
            scheduleAutopilotEvaluationSoon(trigger: .started)
        } else {
            nextAutopilotEvaluationAt = nil
            pendingAutopilotImmediateTrigger = nil
            lastHandledSessionActivityAt = nil
        }

        updateAutopilotState()
    }

    func runAutopilotCheckForTesting() async {
        await runAutopilotEvaluation(trigger: .testing)
    }

    var linkButtonTitle: String {
        switch authAccessState {
        case .unlinked:
            "Link Codex Folder"
        case .locationUnavailable, .accessDenied, .corruptAuthFile, .unsupportedCredentialStore:
            "Relink Codex Folder"
        case .ready, .missingAuthFile:
            "Link Codex Folder"
        }
    }

    func setApplicationActive(_ isActive: Bool) {
        guard isApplicationActive != isActive else {
            return
        }

        isApplicationActive = isActive
        updateRateLimitPollingState()

        if isActive {
            scheduleAutopilotEvaluationSoon(trigger: .appBecameActive)
            Task { @MainActor [weak self] in
                await self?.remoteDeletionCleanup?.consumeHistoryIfNeeded()
                await self?.consumePendingAccountOpenRequestIfNeeded()
            }
        }

        if isRateLimitSurfaceActive {
            requestImmediateRateLimitRefreshForVisibleAccounts()
        }
    }

    func setMenuBarPresented(_ isPresented: Bool) {
        guard isMenuBarPresented != isPresented else {
            return
        }

        isMenuBarPresented = isPresented
        updateRateLimitPollingState()

        if isRateLimitSurfaceActive {
            requestImmediateRateLimitRefreshForVisibleAccounts()
        }
    }

    /// The "selected account" App Intent should only reflect a live account-list
    /// selection, not whichever row happened to be selected the last time the
    /// window was open. The main list view toggles this as it appears/disappears.
    func setPrimarySelectionContextPresented(_ isPresented: Bool) {
        guard isPrimarySelectionContextPresented != isPresented else {
            return
        }

        isPrimarySelectionContextPresented = isPresented
        publishSharedState(immediate: true)
    }

    func setRateLimitVisibility(_ isVisible: Bool, for identityKey: String) {
        guard !identityKey.isEmpty else {
            return
        }

        let currentCount = visibleRateLimitIdentityCounts[identityKey] ?? 0
        let updatedCount = isVisible ? currentCount + 1 : max(currentCount - 1, 0)

        if updatedCount == 0 {
            visibleRateLimitIdentityCounts.removeValue(forKey: identityKey)
        } else {
            visibleRateLimitIdentityCounts[identityKey] = updatedCount
        }

        updateRateLimitPollingState()

        if isVisible, isRateLimitSurfaceActive {
            requestImmediateRateLimitRefresh(for: identityKey)
        }
    }

    func displayedAccounts(from accounts: [StoredAccount]) -> [StoredAccount] {
        AccountsPresentationLogic.displayedAccounts(
            from: accounts,
            searchText: searchText,
            sortCriterion: sortCriterion,
            sortDirection: sortDirection
        )
    }

    /// AppKit asks for the Dock menu synchronously on the main thread, so this
    /// intentionally limits itself to already-persisted account metadata and
    /// only returns accounts that can be switched immediately on this Mac.
    /// The menu reuses the app's active sort settings so the Dock reflects the
    /// same account order without inheriting transient search filtering.
    /// The currently active account remains visible and is marked in the menu.
    func dockAccounts(limit: Int) -> [DockAccountItem] {
        guard limit > 0 else {
            return []
        }

        do {
            let orderedAccounts = AccountsPresentationLogic.sortedAccounts(
                from: try fetchAccounts().filter { account in
                    hasLocalSnapshot(for: account)
                        && !account.identityKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        && !account.isUnavailable
                },
                sortCriterion: sortCriterion,
                sortDirection: sortDirection
            )

            return Array(orderedAccounts.prefix(limit)).map { account in
                DockAccountItem(
                    id: account.id,
                    title: AccountsPresentationLogic.displayName(for: account),
                    iconSystemName: AccountIconOption.resolve(from: account.iconSystemName).systemName,
                    isCurrentAccount: account.identityKey == activeIdentityKey
                )
            }
        } catch {
            logger.error("Couldn't prepare Dock accounts: \(String(describing: error), privacy: .private)")
            return []
        }
    }

    func beginLinkingCodexLocation() {
        pendingLocationAction = nil
        presentCodexFolderPicker()
    }

    private func prepareForInteractiveFilePresentation() {
        guard NSApp.activationPolicy() != .regular else {
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        _ = NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func presentCodexFolderPicker() {
        prepareForInteractiveFilePresentation()

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            let selectedURL = await self.locationPicker.pickCodexFolder()
            if let selectedURL {
                await self.finishLocationImport(.success([selectedURL]))
            } else {
                await self.finishLocationImport(.failure(CocoaError(.userCancelled)))
            }
        }
    }

    func beginAccountArchiveImport() {
        isShowingAccountArchiveImporter = true
    }

    func handleAccountArchiveImport(_ result: Result<URL, any Error>) {
        Task { [weak self] in
            guard let self else {
                return
            }

            await self.finishAccountArchiveImport(result)
        }
    }

    func handleDroppedAccountArchiveURLs(_ urls: [URL]) {
        Task { [weak self] in
            guard let self else {
                return
            }

            await self.importAccountArchives(from: urls)
        }
    }

    func handleIncomingAccountArchiveURL(_ url: URL) {
        Task { [weak self] in
            guard let self else {
                return
            }

            await self.importAccountArchives(from: [url])
        }
    }

    func handleLocationImport(_ result: Result<[URL], any Error>) {
        Task { [weak self] in
            guard let self else {
                return
            }

            await self.finishLocationImport(result)
        }
    }

    func refresh() {
        Task { [weak self] in
            guard let self else {
                return
            }

            await self.performRefresh(showUnexpectedErrors: true)
        }
    }

    func captureCurrentAccount() {
        guard canCaptureCurrentAccount else {
            return
        }

        isCapturingCurrentAccount = true
        captureTask = Task { [weak self] in
            guard let self else {
                return
            }

            defer {
                self.isCapturingCurrentAccount = false
                self.captureTask = nil
            }

            await self.addAccountNow()
        }
    }

    func cancelAccountCapture() {
        captureTask?.cancel()
    }

    private func addAccountNow() async {
        await waitForInitializationIfNeeded()
        guard !Task.isCancelled else {
            return
        }

        if await tryCaptureCurrentAuthJsonForAddFlow() {
            return
        }
        guard !Task.isCancelled else {
            return
        }

        await startOfficialLoginAndImport()
    }

    func beginExportSelectedAccount() {
        Task { [weak self] in
            guard let self else {
                return
            }

            await self.exportSelectedAccountArchive()
        }
    }

    func login(accountID: UUID) {
        if accountID == Self.noneAccountSelectionID {
            switchToNone()
            return
        }

        let operationID = UUID()
        activeSwitchOperationID = operationID
        switchTask?.cancel()
        switchTask = Task { [weak self] in
            guard let self else {
                return
            }

            await self.switchToAccountNow(id: accountID, operationID: operationID)
        }
    }

    func switchSelectedAccount() {
        guard selection.count == 1, let accountID = selection.first else {
            return
        }

        if accountID == Self.noneAccountSelectionID {
            switchToNone()
        } else {
            login(accountID: accountID)
        }
    }

    func beginRenamingSelectedAccount() {
        guard selection.count == 1, let accountID = selection.first else {
            return
        }

        guard accountID != Self.noneAccountSelectionID else {
            return
        }

        beginRenaming(accountID: accountID)
    }

    func setPinned(_ isPinned: Bool, for accountID: UUID) {
        guard accountID != Self.noneAccountSelectionID else {
            return
        }

        do {
            guard let account = try account(withID: accountID) else {
                throw ControllerError.accountNotFound
            }

            let normalizedLegacyFields = account.normalizeLegacyLocalOnlyFields()
            guard account.isPinned != isPinned || normalizedLegacyFields else {
                return
            }

            account.isPinned = isPinned
            try requireModelContext().save()
            publishSharedState()
        } catch {
            present(error, title: isPinned ? "Couldn't Pin Account" : "Couldn't Unpin Account")
        }
    }

    func setSelectedAccountPinned(_ isPinned: Bool) {
        guard let selectedAccountID else {
            return
        }

        setPinned(isPinned, for: selectedAccountID)
    }

    func beginRenaming(accountID: UUID) {
        guard accountID != Self.noneAccountSelectionID else {
            return
        }

        selection = [accountID]
        renameTargetID = accountID
    }

    func cancelRename(for accountID: UUID) {
        guard renameTargetID == accountID else {
            return
        }

        renameTargetID = nil
    }

    func commitRename(for accountID: UUID, proposedName: String) {
        do {
            guard let account = try account(withID: accountID) else {
                throw ControllerError.accountNotFound
            }

            guard let trimmedName = AccountsPresentationLogic.normalizedRenamedAccountName(proposedName) else {
                renameTargetID = nil
                return
            }

            let normalizedLegacyFields = account.normalizeLegacyLocalOnlyFields()
            guard account.name != trimmedName || normalizedLegacyFields else {
                renameTargetID = nil
                return
            }

            account.name = trimmedName
            try requireModelContext().save()
            renameTargetID = nil
            publishSharedState()
        } catch {
            present(error, title: "Couldn't Rename Account")
        }
    }

    func setIcon(_ icon: AccountIconOption, for accountID: UUID) {
        guard accountID != Self.noneAccountSelectionID else {
            return
        }

        do {
            guard let account = try account(withID: accountID) else {
                throw ControllerError.accountNotFound
            }

            let resolvedSystemName = AccountIconOption.resolve(from: icon.systemName).systemName
            let normalizedLegacyFields = account.normalizeLegacyLocalOnlyFields()
            guard account.iconSystemName != resolvedSystemName || normalizedLegacyFields else {
                return
            }

            account.iconSystemName = resolvedSystemName
            try requireModelContext().save()
            publishSharedState()
        } catch {
            present(error, title: "Couldn't Change Icon")
        }
    }

    func setSelectedAccountIcon(_ icon: AccountIconOption) {
        guard let selectedAccountID else {
            return
        }

        setIcon(icon, for: selectedAccountID)
    }

    func removeSelectedAccounts() {
        Task { [weak self] in
            guard let self else {
                return
            }

            await self.removeAccountsNow(withIDs: self.selection)
        }
    }

    func removeAccounts(withIDs ids: Set<UUID>) {
        Task { [weak self] in
            guard let self else {
                return
            }

            await self.removeAccountsNow(withIDs: ids)
        }
    }

    func presentUnavailableAccountRecoveryPrompt(for account: StoredAccount) {
        unavailableAccountRecoveryPrompt = UnavailableAccountRecoveryPrompt(
            accountID: account.id,
            accountName: AccountsPresentationLogic.displayName(for: account),
            reason: account.unavailableReason
        )
    }

    func removeUnavailableAccountFromPrompt(_ prompt: UnavailableAccountRecoveryPrompt) {
        unavailableAccountRecoveryPrompt = nil
        removeAccounts(withIDs: [prompt.accountID])
    }

    func keepUnavailableAccountFromPrompt() {
        unavailableAccountRecoveryPrompt = nil
    }

    func removeAllAccounts() {
        Task { [weak self] in
            guard let self else {
                return
            }

            await self.removeAllAccountsNow()
        }
    }

    func reorderDraggedAccounts(_ items: [String], to destinationIndex: Int, visibleAccounts: [StoredAccount]) {
        guard
            canEditCustomOrder,
            !visibleAccounts.isEmpty
        else {
            return
        }

        let movingIDs = Self.draggedAccountIDs(from: items)
        moveAccounts(withIDs: movingIDs, to: destinationIndex, visibleAccounts: visibleAccounts)
    }

    /// Persists the visible list order produced by SwiftUI's binding-based
    /// editable list API. The caller must provide the full visible sequence so
    /// the controller can reapply the pinned/unpinned lane invariant before
    /// saving.
    func persistCustomOrder(for reorderedVisibleIDs: [UUID], visibleAccounts: [StoredAccount]) {
        guard
            canEditCustomOrder,
            !visibleAccounts.isEmpty,
            reorderedVisibleIDs.count == visibleAccounts.count
        else {
            return
        }

        let visibleIDs = visibleAccounts.map(\.id)
        guard Set(reorderedVisibleIDs) == Set(visibleIDs) else {
            return
        }

        let accountsByID = Dictionary(uniqueKeysWithValues: visibleAccounts.map { ($0.id, $0) })
        let reorderedAccounts = reorderedVisibleIDs.compactMap { accountsByID[$0] }
        guard reorderedAccounts.count == visibleAccounts.count else {
            return
        }

        persistCustomOrder(for: reorderedAccounts)
    }

    func moveSelection(direction: MoveCommandDirection, visibleAccounts: [StoredAccount]) {
        guard canEditCustomOrder else {
            return
        }

        let orderedSelection = visibleAccounts.compactMap { account in
            selection.contains(account.id) ? account.id : nil
        }
        guard !orderedSelection.isEmpty else {
            return
        }

        let selectedIndexes = visibleAccounts.indices.filter { index in
            selection.contains(visibleAccounts[index].id)
        }
        guard
            let firstSelectedIndex = selectedIndexes.first,
            let lastSelectedIndex = selectedIndexes.last
        else {
            return
        }

        let destinationIndex: Int
        switch direction {
        case .up:
            destinationIndex = max(firstSelectedIndex - 1, 0)
        case .down:
            destinationIndex = min(lastSelectedIndex + 2, visibleAccounts.count)
        default:
            return
        }

        moveAccounts(withIDs: orderedSelection, to: destinationIndex, visibleAccounts: visibleAccounts)
    }

    @discardableResult
    func captureCurrentAccountNow(allowsInteractiveRecovery: Bool = true) async -> Bool {
        await captureCurrentAccountNow(
            allowsInteractiveRecovery: allowsInteractiveRecovery,
            managesCaptureState: true
        )
    }

    private func tryCaptureCurrentAuthJsonForAddFlow() async -> Bool {
        do {
            let readResult = try await authFileManager.readAuthFile()
            guard !readResult.contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return false
            }

            let snapshot = try await parseSnapshot(from: readResult.contents)
            let modelContext = try requireModelContext()
            let accounts = try fetchAccounts()

            if let match = accountMatch(for: snapshot, in: accounts) {
                let recoveredUnavailableAccount = match.recoversUnavailableAccount
                _ = try await storeSnapshot(snapshot, on: match.account)
                _ = AccountAvailabilityUpdater.markAvailable(match.account)
                let removedUnavailableDuplicates = await removeUnavailableReplacementDuplicates(
                    matching: snapshot,
                    keeping: match.account,
                    from: accounts,
                    in: modelContext
                )
                try modelContext.save()
                requestImmediateRateLimitRefresh(for: snapshot.identityKey)
                guard recoveredUnavailableAccount || removedUnavailableDuplicates else {
                    return false
                }

                selection = [match.account.id]
                activeIdentityKey = snapshot.identityKey
                authAccessState = .ready(linkedFolder: readResult.url.deletingLastPathComponent())
                searchText = ""
                publishSharedState()
                return true
            }

            try await addStoredAccount(
                from: snapshot,
                at: Date(),
                existingAccounts: accounts,
                in: modelContext
            )
            activeIdentityKey = snapshot.identityKey
            authAccessState = .ready(linkedFolder: readResult.url.deletingLastPathComponent())
            searchText = ""
            try modelContext.save()
            publishSharedState()
            requestImmediateRateLimitRefresh(for: snapshot.identityKey)
            return true
        } catch {
            logger.debug("Plus-button current auth capture skipped: \(String(describing: error), privacy: .private)")
            return false
        }
    }

    private func startOfficialLoginAndImport() async {
        do {
            let result = try await officialLoginCoordinator.login()
            let modelContext = try requireModelContext()
            let accounts = try fetchAccounts()
            let importedAt = Date()

            if let match = accountMatch(for: result.parsedAuth, in: accounts) {
                let recoveredUnavailableAccount = match.recoversUnavailableAccount
                _ = try await storeSnapshot(result.parsedAuth, on: match.account)
                _ = AccountAvailabilityUpdater.markAvailable(match.account, checkedAt: importedAt)
                let removedUnavailableDuplicates = await removeUnavailableReplacementDuplicates(
                    matching: result.parsedAuth,
                    keeping: match.account,
                    from: accounts,
                    in: modelContext
                )
                selection = [match.account.id]
                try modelContext.save()
                publishSharedState()
                requestImmediateRateLimitRefresh(for: result.parsedAuth.identityKey)
                if !recoveredUnavailableAccount && !removedUnavailableDuplicates {
                    present(
                        UserFacingAlert(
                            title: "Account Already Saved",
                            message: "This account is already in Codex Switcher. Its saved auth snapshot was refreshed."
                        )
                    )
                }
                return
            }

            try await addStoredAccount(
                from: result.parsedAuth,
                at: importedAt,
                existingAccounts: accounts,
                in: modelContext
            )
            searchText = ""
            try modelContext.save()
            publishSharedState()
            requestImmediateRateLimitRefresh(for: result.parsedAuth.identityKey)
        } catch is CancellationError {
            return
        } catch CodexOfficialLoginError.cancelled {
            return
        } catch {
            present(error, title: "Couldn't Add Account")
        }
    }

    @discardableResult
    private func captureCurrentAccountNow(
        allowsInteractiveRecovery: Bool,
        managesCaptureState: Bool
    ) async -> Bool {
        if managesCaptureState {
            guard !isCapturingCurrentAccount else {
                return false
            }

            isCapturingCurrentAccount = true
        }

        defer {
            if managesCaptureState {
                isCapturingCurrentAccount = false
            }
        }

        await waitForInitializationIfNeeded()

        do {
            let readResult = try await authFileManager.readAuthFile()
            let snapshot = try await parseSnapshot(from: readResult.contents)
            let modelContext = try requireModelContext()
            let accounts = try fetchAccounts()
            let captureAt = Date()

            if let match = accountMatch(for: snapshot, in: accounts) {
                _ = try await storeSnapshot(snapshot, on: match.account)
                _ = AccountAvailabilityUpdater.markAvailable(match.account, checkedAt: captureAt)
                _ = StoredAccountMutations.applyLastLogin(captureAt, to: match.account)
                _ = await removeUnavailableReplacementDuplicates(
                    matching: snapshot,
                    keeping: match.account,
                    from: accounts,
                    in: modelContext
                )
                selection = [match.account.id]
            } else {
                try await addStoredAccount(
                    from: snapshot,
                    at: captureAt,
                    existingAccounts: accounts,
                    in: modelContext
                )
            }

            try modelContext.save()
            searchText = ""
            activeIdentityKey = snapshot.identityKey
            authAccessState = .ready(linkedFolder: readResult.url.deletingLastPathComponent())
            publishSharedState()
            requestImmediateRateLimitRefresh(for: snapshot.identityKey)
            return true
        } catch {
            await handleCaptureCurrentAccountError(
                error,
                title: "Couldn't Save Account",
                allowsInteractiveRecovery: allowsInteractiveRecovery
            )
            return false
        }
    }

    private func addStoredAccount(
        from snapshot: CodexAuthSnapshot,
        at addedAt: Date,
        existingAccounts: [StoredAccount],
        in modelContext: ModelContext
    ) async throws {
        guard existingAccounts.count < 1_000 else {
            throw ControllerError.accountLimitReached
        }

        let nextCustomOrder = (existingAccounts.map(\.customOrder).max() ?? -1) + 1
        let account = StoredAccount(
            identityKey: snapshot.identityKey,
            name: defaultName(for: snapshot, existingAccounts: existingAccounts),
            lastLoginAt: addedAt,
            customOrder: nextCustomOrder,
            authModeRaw: snapshot.authMode.rawValue,
            emailHint: snapshot.email,
            accountIdentifier: snapshot.accountIdentifier,
            lastAvailabilityCheckAt: addedAt
        )

        _ = try await storeSnapshot(snapshot, on: account)
        _ = AccountAvailabilityUpdater.markAvailable(account, checkedAt: addedAt)
        modelContext.insert(account)
        selection = [account.id]
    }

    func removeUnavailableAccountsIfAutomaticRemoveEnabled() {
        Task { [weak self] in
            guard let self else {
                return
            }

            await self.removeUnavailableAccountsIfNeeded()
        }
    }

    private func removeUnavailableAccountsIfNeeded() async {
        await waitForInitializationIfNeeded()

        guard CodexSharedPreferences.automaticallyRemoveAccounts else {
            return
        }

        do {
            let unavailableAccountIDs = Set(
                try fetchAccounts()
                    .filter(\.isUnavailable)
                    .map(\.id)
            )
            guard !unavailableAccountIDs.isEmpty else {
                return
            }

            _ = await removeAccountsNow(
                withIDs: unavailableAccountIDs,
                allowsInteractiveRecovery: false
            )
        } catch {
            logger.error("Couldn't scan unavailable accounts for automatic removal: \(String(describing: error), privacy: .private)")
        }
    }

    private struct SnapshotAccountMatch {
        let account: StoredAccount
        let recoversUnavailableAccount: Bool
    }

    private func accountMatch(
        for snapshot: CodexAuthSnapshot,
        in accounts: [StoredAccount]
    ) -> SnapshotAccountMatch? {
        if let exactAccount = accounts.first(where: { $0.identityKey == snapshot.identityKey }) {
            return SnapshotAccountMatch(
                account: exactAccount,
                recoversUnavailableAccount: exactAccount.isUnavailable
            )
        }

        guard let replacement = unavailableReplacementCandidates(
            matching: snapshot,
            in: accounts
        ).first else {
            return nil
        }

        return SnapshotAccountMatch(account: replacement, recoversUnavailableAccount: true)
    }

    @discardableResult
    private func removeUnavailableReplacementDuplicates(
        matching snapshot: CodexAuthSnapshot,
        keeping keptAccount: StoredAccount,
        from accounts: [StoredAccount],
        in modelContext: ModelContext
    ) async -> Bool {
        let duplicates = unavailableReplacementCandidates(matching: snapshot, in: accounts)
            .filter { $0.id != keptAccount.id }
        guard !duplicates.isEmpty else {
            return false
        }

        let duplicateIDs = Set(duplicates.map(\.id))
        let duplicateIdentityKeys = Set(duplicates.map(\.identityKey).filter { !$0.isEmpty })
        let remainingIdentityKeys = Set(
            accounts
                .filter { !duplicateIDs.contains($0.id) }
                .map(\.identityKey)
                .filter { !$0.isEmpty }
        )

        for duplicate in duplicates {
            if !remainingIdentityKeys.contains(duplicate.identityKey) {
                try? await secretStore.deleteSnapshot(forIdentityKey: duplicate.identityKey)
                try? await syncedRateLimitCredentialStore.delete(forIdentityKey: duplicate.identityKey)
            }

            modelContext.delete(duplicate)
        }

        selection.subtract(duplicateIDs)
        if let renameTargetID, duplicateIDs.contains(renameTargetID) {
            self.renameTargetID = nil
        }

        for identityKey in duplicateIdentityKeys {
            rateLimitSnapshotsByIdentityKey.removeValue(forKey: identityKey)
            visibleRateLimitIdentityCounts.removeValue(forKey: identityKey)
            pendingForcedRateLimitRefreshes.remove(identityKey)
            rateLimitRefreshesInFlight.remove(identityKey)
            rateLimitFailureBackoffUntil.removeValue(forKey: identityKey)
            rateLimitFailureBackoffDurations.removeValue(forKey: identityKey)
        }

        return true
    }

    private func unavailableReplacementCandidates(
        matching snapshot: CodexAuthSnapshot,
        in accounts: [StoredAccount]
    ) -> [StoredAccount] {
        accounts
            .filter { account in
                guard account.isUnavailable else {
                    return false
                }

                return Self.unavailableAccount(account, matches: snapshot)
            }
            .sorted { lhs, rhs in
                let snapshotIdentifier = Self.normalizedAccountMatchValue(snapshot.accountIdentifier)
                let lhsIdentifierMatches = snapshotIdentifier != nil
                    && Self.normalizedAccountMatchValue(lhs.accountIdentifier) == snapshotIdentifier
                let rhsIdentifierMatches = snapshotIdentifier != nil
                    && Self.normalizedAccountMatchValue(rhs.accountIdentifier) == snapshotIdentifier

                if lhsIdentifierMatches != rhsIdentifierMatches {
                    return lhsIdentifierMatches
                }

                return lhs.createdAt < rhs.createdAt
            }
    }

    private static func unavailableAccount(
        _ account: StoredAccount,
        matches snapshot: CodexAuthSnapshot
    ) -> Bool {
        if account.identityKey == snapshot.identityKey {
            return true
        }

        if let accountIdentifier = normalizedAccountMatchValue(account.accountIdentifier),
           let snapshotIdentifier = normalizedAccountMatchValue(snapshot.accountIdentifier),
           accountIdentifier == snapshotIdentifier {
            return true
        }

        if let accountEmail = normalizedAccountMatchValue(account.emailHint),
           let snapshotEmail = normalizedAccountMatchValue(snapshot.email),
           accountEmail == snapshotEmail {
            return true
        }

        return false
    }

    private nonisolated static func normalizedAccountMatchValue(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return nil
        }

        return trimmedValue.lowercased()
    }

    func switchToAccountNow(
        id: UUID,
        operationID: UUID? = nil,
        allowsInteractiveRecovery: Bool = true,
        notificationKind: CodexSwitchNotificationKind = .userInitiated
    ) async {
        await waitForInitializationIfNeeded()

        let resolvedOperationID = operationID ?? UUID()
        activeSwitchOperationID = resolvedOperationID
        isSwitching = true
        defer {
            if activeSwitchOperationID == resolvedOperationID {
                isSwitching = false
            }
        }

        do {
            let modelContext = try requireModelContext()
            let targetAccount = try requireAccount(withID: id)
            guard !targetAccount.isUnavailable else {
                if allowsInteractiveRecovery {
                    presentUnavailableAccountRecoveryPrompt(for: targetAccount)
                } else {
                    throw ControllerError.accountUnavailable
                }
                return
            }

            let desiredAuthContents = try await loadStoredSnapshot(for: targetAccount)
            let loginAt = Date()

            if activeIdentityKey == targetAccount.identityKey {
                if let live = try? await liveAuthSnapshot(),
                   live.snapshot.identityKey == targetAccount.identityKey {
                    activeIdentityKey = targetAccount.identityKey
                    authAccessState = .ready(linkedFolder: live.read.url.deletingLastPathComponent())
                    selection = [targetAccount.id]
                    renameTargetID = nil

                    let normalizedLiveContents = try? CodexAuthSnapshotNormalizer
                        .normalizedForCodexRuntime(live.read.contents)
                    if let normalizedLiveContents,
                       normalizedLiveContents != live.read.contents {
                        try await authFileManager.writeAuthFile(normalizedLiveContents)
                        let normalizedLiveSnapshot = try await parseSnapshot(from: normalizedLiveContents)
                        _ = try await storeSnapshot(normalizedLiveSnapshot, on: targetAccount)
                    } else if live.read.contents != desiredAuthContents {
                        do {
                            _ = try await storeSnapshot(live.snapshot, on: targetAccount)
                        } catch {
                            logger.error(
                                "Couldn't refresh stored snapshot for already-active account \(targetAccount.identityKey, privacy: .public): \(String(describing: error), privacy: .private)"
                            )
                        }
                    }

                    persistSuccessfulLoginMetadata(
                        for: targetAccount,
                        at: loginAt,
                        in: modelContext,
                        allowsInteractiveRecovery: allowsInteractiveRecovery,
                        partialSuccessTitle: "Account Selected"
                    )
                    publishSharedState()
                    requestImmediateRateLimitRefresh(for: targetAccount.identityKey)
                    return
                }

                activeIdentityKey = nil
            }

            if let currentRead = try? await authFileManager.readAuthFile(), currentRead.contents == desiredAuthContents {
                activeIdentityKey = targetAccount.identityKey
                authAccessState = .ready(linkedFolder: currentRead.url.deletingLastPathComponent())
                selection = [targetAccount.id]
                renameTargetID = nil
                persistSuccessfulLoginMetadata(
                    for: targetAccount,
                    at: loginAt,
                    in: modelContext,
                    allowsInteractiveRecovery: allowsInteractiveRecovery,
                    partialSuccessTitle: "Account Selected"
                )
                publishSharedState()
                requestImmediateRateLimitRefresh(for: targetAccount.identityKey)
                return
            }

            await preserveCurrentLiveSnapshotIfKnown()
            try Task.checkCancellation()

            try await authFileManager.writeAuthFile(desiredAuthContents)

            let verifiedRead = try await authFileManager.readAuthFile()
            let verifiedSnapshot = try await parseSnapshot(from: verifiedRead.contents)
            guard verifiedSnapshot.identityKey == targetAccount.identityKey else {
                throw AuthFileAccessError.verificationFailed(verifiedRead.url)
            }

            activeIdentityKey = verifiedSnapshot.identityKey
            authAccessState = .ready(linkedFolder: verifiedRead.url.deletingLastPathComponent())
            selection = [targetAccount.id]
            renameTargetID = nil
            persistSuccessfulLoginMetadata(
                for: targetAccount,
                at: loginAt,
                in: modelContext,
                allowsInteractiveRecovery: allowsInteractiveRecovery,
                partialSuccessTitle: "Account Switched"
            )

            publishSharedState()
            requestImmediateRateLimitRefresh(for: targetAccount.identityKey)
            notePotentialPendingCodexRestart(for: .account(name: targetAccount.name))
            await notificationManager.postSwitchNotification(
                for: targetAccount.name,
                kind: notificationKind
            )
        } catch is CancellationError {
            return
        } catch {
            await handleExpectedAuthOperationError(
                error,
                title: "Couldn't Switch Account",
                retryAction: .switchAccount(id),
                allowsInteractiveRecovery: allowsInteractiveRecovery
            )
        }
    }

    func switchToNone() {
        let operationID = UUID()
        activeSwitchOperationID = operationID
        switchTask?.cancel()
        switchTask = Task { [weak self] in
            guard let self else {
                return
            }

            await self.switchToNoneNow(operationID: operationID)
        }
    }

    private func switchToNoneNow(operationID: UUID) async {
        await waitForInitializationIfNeeded()

        activeSwitchOperationID = operationID
        isSwitching = true
        defer {
            if activeSwitchOperationID == operationID {
                isSwitching = false
            }
        }

        do {
            await preserveCurrentLiveSnapshotIfKnown()
            try Task.checkCancellation()
            try await authFileManager.deleteAuthFile()

            let linkedLocation = try? await authFileManager.linkedLocation()
            activeIdentityKey = nil
            selection = [Self.noneAccountSelectionID]
            renameTargetID = nil

            if let linkedLocation {
                authAccessState = .missingAuthFile(
                    linkedFolder: linkedLocation.folderURL,
                    credentialStoreHint: linkedLocation.credentialStoreHint
                )
            } else {
                authAccessState = .unlinked
            }

            publishSharedState()
            notePotentialPendingCodexRestart(for: .none)
        } catch is CancellationError {
            return
        } catch {
            await handleExpectedAuthOperationError(
                error,
                title: "Couldn't Select None",
                retryAction: .switchAccount(Self.noneAccountSelectionID)
            )
        }
    }

    private func liveAuthSnapshot() async throws -> (
        read: AuthFileReadResult,
        snapshot: CodexAuthSnapshot
    ) {
        let read = try await authFileManager.readAuthFile()
        let snapshot = try await parseSnapshot(from: read.contents)
        return (read, snapshot)
    }

    @discardableResult
    func removeAccountsNow(withIDs ids: Set<UUID>, allowsInteractiveRecovery: Bool = true) async -> Bool {
        await waitForInitializationIfNeeded()

        guard !ids.isEmpty else {
            return true
        }

        do {
            let modelContext = try requireModelContext()
            let allAccounts = try fetchAccounts()
            let accountsToDelete = allAccounts.filter { ids.contains($0.id) }
            guard !accountsToDelete.isEmpty else {
                return true
            }
            let remainingIdentityKeys = Set(
                allAccounts
                    .filter { !ids.contains($0.id) }
                    .map(\.identityKey)
                    .filter { !$0.isEmpty }
            )
            let deletedIdentityKeys = Set(
                accountsToDelete
                    .map(\.identityKey)
                    .filter { !$0.isEmpty }
            )

            for account in accountsToDelete {
                if !remainingIdentityKeys.contains(account.identityKey) {
                    try? await secretStore.deleteSnapshot(forIdentityKey: account.identityKey)
                    try? await syncedRateLimitCredentialStore.delete(forIdentityKey: account.identityKey)
                }
                modelContext.delete(account)
            }

            selection.subtract(ids)
            if let renameTargetID, ids.contains(renameTargetID) {
                self.renameTargetID = nil
            }

            for identityKey in deletedIdentityKeys {
                rateLimitSnapshotsByIdentityKey.removeValue(forKey: identityKey)
                visibleRateLimitIdentityCounts.removeValue(forKey: identityKey)
                pendingForcedRateLimitRefreshes.remove(identityKey)
                rateLimitRefreshesInFlight.remove(identityKey)
                rateLimitFailureBackoffUntil.removeValue(forKey: identityKey)
                rateLimitFailureBackoffDurations.removeValue(forKey: identityKey)
            }

            try modelContext.save()
            publishSharedState()
            return true
        } catch {
            guard allowsInteractiveRecovery else {
                logger.error("Couldn't remove account(s): \(String(describing: error), privacy: .private)")
                return false
            }

            present(error, title: "Couldn't Remove Account")
            return false
        }
    }

    func removeAllAccountsNow() async {
        await waitForInitializationIfNeeded()

        do {
            let allAccountIDs = Set(try fetchAccounts().map(\.id))
            await removeAccountsNow(withIDs: allAccountIDs)
        } catch {
            present(error, title: "Couldn't Remove Accounts")
        }
    }

    func refreshAuthStateForTesting() async {
        await waitForInitializationIfNeeded()
        await refreshAuthState(showUnexpectedErrors: false)
    }

    func refreshForTesting() async {
        await performRefresh(showUnexpectedErrors: true)
    }

    func runAutopilotLaunchTriggerForTesting() async {
        await runAutopilotEvaluation(trigger: .started)
    }

    func runAutopilotFocusTriggerForTesting() async {
        await runAutopilotEvaluation(trigger: .appBecameActive)
    }

    func runAutopilotWakeTriggerForTesting() async {
        await runAutopilotEvaluation(trigger: .systemWoke)
    }

    func runAutopilotSessionQuietTriggerForTesting(observedAt: Date) async {
        noteRecentSessionActivityForTesting(observedAt: observedAt)
        await runAutopilotEvaluation(trigger: .sessionBecameQuiet)
    }

    func runPeriodicRateLimitRefreshPassForTesting() async {
        await refreshDueRateLimitsIfNeeded()
    }

    func handleRemoteSwitchSignalForTesting(_ signal: CodexSharedSwitchSignal) async {
        await handleRemoteSwitchSignal(signal)
    }

    func scheduledAutopilotWouldRunNowForTesting() -> Bool {
        let now = Date()
        let previousScheduledEvaluation = nextAutopilotEvaluationAt
        let previousImmediateTrigger = pendingAutopilotImmediateTrigger

        defer {
            nextAutopilotEvaluationAt = previousScheduledEvaluation
            pendingAutopilotImmediateTrigger = previousImmediateTrigger
        }

        nextAutopilotEvaluationAt = now.addingTimeInterval(-1)
        pendingAutopilotImmediateTrigger = nil
        return autopilotTriggerDue(relativeTo: now) == .scheduled
    }

    func handleSystemWakeForTesting() {
        isSystemSleeping = false
        areScreensSleeping = false
        if isRateLimitSurfaceActive {
            requestImmediateRateLimitRefreshForVisibleAccounts()
        }
        scheduleAutopilotEvaluationSoon(after: Self.autopilotWakeDelay, trigger: .systemWoke)
    }

    func noteRecentSessionActivityForTesting(observedAt: Date) {
        guard observedAt > (lastObservedSessionActivityAt ?? .distantPast) else {
            return
        }

        lastObservedSessionActivityAt = observedAt
        scheduleAutopilotEvaluationAfterRecentSessionActivity(observedAt: observedAt)
    }

    func handleLocationImportForTesting(_ result: Result<[URL], any Error>) async {
        await waitForInitializationIfNeeded()
        await finishLocationImport(result)
    }

    @discardableResult
    func importAccountArchivesForTesting(from urls: [URL]) async -> Bool {
        await waitForInitializationIfNeeded()
        return await importAccountArchives(from: urls)
    }

    private func parseSnapshot(from contents: String) async throws -> CodexAuthSnapshot {
        // Decode auth payloads away from the main actor so UI updates are not
        // blocked by file parsing or future auth.json schema growth.
        try await Task.detached(priority: .userInitiated) {
            try CodexAuthFile.parse(contents: contents)
        }.value
    }

    private func finishAccountArchiveImport(_ result: Result<URL, any Error>) async {
        switch result {
        case .success(let url):
            _ = await importAccountArchives(from: [url])
        case .failure(let error):
            let nsError = error as NSError
            guard nsError.domain != NSCocoaErrorDomain || nsError.code != NSUserCancelledError else {
                return
            }

            present(error, title: "Couldn't Import Account")
        }
    }

    @discardableResult
    private func importAccountArchives(from urls: [URL]) async -> Bool {
        await waitForInitializationIfNeeded()

        let accountArchiveURLs = urls.filter(Self.isAccountArchiveURL)
        guard !accountArchiveURLs.isEmpty else {
            present(
                UserFacingAlert(
                    title: "Couldn't Import Account",
                    message: ControllerError.noSupportedAccountArchives.errorDescription ?? "No supported .cxa files were provided."
                )
            )
            return false
        }

        do {
            let modelContext = try requireModelContext()
            var allAccounts = try fetchAccounts()
            var importedAccountID: UUID?
            var importedIdentityKey: String?
            var importedAnyAccounts = false
            var failureMessages: [String] = []

            for url in accountArchiveURLs {
                do {
                    let archive = try Self.loadAccountArchive(from: url)
                    for (accountIndex, archivedAccount) in archive.accounts.enumerated() {
                        do {
                            let snapshot = try await parseSnapshot(from: archivedAccount.snapshotContents)

                            if let archivedIdentityKey = archivedAccount.identityKey?.trimmingCharacters(in: .whitespacesAndNewlines),
                               !archivedIdentityKey.isEmpty,
                               archivedIdentityKey != snapshot.identityKey {
                                throw ControllerError.accountArchiveIdentityMismatch
                            }

                            if let existingAccount = allAccounts.first(where: { $0.identityKey == snapshot.identityKey }) {
                                _ = try await storeSnapshot(
                                    snapshot,
                                    importedRateLimitCredential: archivedAccount.rateLimitCredential,
                                    on: existingAccount
                                )
                                _ = Self.applyImportedArchiveMetadata(archivedAccount, to: existingAccount)
                                _ = Self.applyImportedRateLimits(
                                    archivedAccount.rateLimits,
                                    identityKey: snapshot.identityKey,
                                    to: existingAccount
                                )
                                _ = StoredAccountMutations.applyLastLogin(
                                    archivedAccount.lastLoginAt,
                                    to: existingAccount
                                )
                                // Re-importing an unchanged archive is still a valid
                                // success case: keep the existing account selected even
                                // when the imported contents match the local copy.
                                importedAnyAccounts = true
                                importedAccountID = existingAccount.id
                                importedIdentityKey = snapshot.identityKey
                                continue
                            }

                            guard allAccounts.count < 1_000 else {
                                throw ControllerError.accountLimitReached
                            }

                            let nextCustomOrder = (allAccounts.map(\.customOrder).max() ?? -1) + 1
                            let account = StoredAccount(
                                identityKey: snapshot.identityKey,
                                name: archivedAccount.preferredStoredName
                                    ?? defaultName(for: snapshot, existingAccounts: allAccounts),
                                lastLoginAt: archivedAccount.lastLoginAt,
                                customOrder: nextCustomOrder,
                                authModeRaw: snapshot.authMode.rawValue,
                                emailHint: snapshot.email,
                                accountIdentifier: snapshot.accountIdentifier,
                                iconSystemName: archivedAccount.resolvedIconSystemName
                            )

                            _ = try await storeSnapshot(
                                snapshot,
                                importedRateLimitCredential: archivedAccount.rateLimitCredential,
                                on: account
                            )
                            _ = Self.applyImportedRateLimits(
                                archivedAccount.rateLimits,
                                identityKey: snapshot.identityKey,
                                to: account
                            )
                            modelContext.insert(account)
                            allAccounts.append(account)
                            importedAnyAccounts = true
                            importedAccountID = account.id
                            importedIdentityKey = snapshot.identityKey
                        } catch {
                            let accountLabel = archivedAccount.preferredStoredName
                                ?? archivedAccount.identityKey
                                ?? "Account \(accountIndex + 1)"
                            failureMessages.append(
                                "\(url.lastPathComponent) • \(accountLabel): \(error.localizedDescription)"
                            )
                        }
                    }
                } catch {
                    failureMessages.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }

            guard importedAnyAccounts else {
                let message = failureMessages.joined(separator: "\n")
                present(
                    UserFacingAlert(
                        title: "Couldn't Import Account",
                        message: message.isEmpty ? "Codex Switcher couldn't import that .cxa file." : message
                    )
                )
                return false
            }

            try modelContext.save()
            searchText = ""
            if let importedAccountID {
                selection = [importedAccountID]
            }
            publishSharedState()

            if let importedIdentityKey {
                requestImmediateRateLimitRefresh(for: importedIdentityKey)
            }

            if !failureMessages.isEmpty {
                present(
                    UserFacingAlert(
                        title: "Imported with Issues",
                        message: failureMessages.joined(separator: "\n")
                    )
                )
            }

            return true
        } catch {
            present(error, title: "Couldn't Import Account")
            return false
        }
    }

    private func exportSelectedAccountArchive() async {
        guard let selectedAccountID else {
            return
        }

        do {
            let account = try requireAccount(withID: selectedAccountID)
            let exportItem = archiveTransferItem(for: account)

            guard await exportItem.canExport() else {
                throw ControllerError.accountNeedsLocalSnapshotForExport
            }

            // Drive the macOS menu export through AppKit directly. The generic
            // SwiftUI file-export bridge builds an NSFileWrapper for the
            // Transferable path, and that wrapper crashed here in practice when
            // AppKit rejected an empty preferred filename during export.
            guard let destinationURL = await presentAccountArchiveSavePanel(
                suggestedFilename: exportItem.defaultFilename
            ) else {
                return
            }

            let archiveData = try await archiveExporter.exportData(for: exportItem.request)
            try archiveData.write(to: destinationURL, options: .atomic)
        } catch {
            present(error, title: "Couldn't Export Account")
        }
    }

    private static func applyImportedArchiveMetadata(
        _ archive: CodexAccountArchive.Account,
        to account: StoredAccount
    ) -> Bool {
        var didChange = false

        if let importedName = archive.preferredStoredName,
           (account.name.isEmpty || isGeneratedAccountName(account.name)) {
            if account.name != importedName {
                account.name = importedName
                didChange = true
            }
        }

        let importedIconSystemName = archive.resolvedIconSystemName
        if account.iconSystemName == AccountIconOption.defaultOption.systemName,
           importedIconSystemName != AccountIconOption.defaultOption.systemName {
            account.iconSystemName = importedIconSystemName
            didChange = true
        }

        return didChange
    }

    @discardableResult
    private static func applyImportedRateLimits(
        _ rateLimits: CodexAccountArchive.Account.RateLimits?,
        identityKey: String,
        to account: StoredAccount
    ) -> Bool {
        guard let snapshot = rateLimits?.snapshot(identityKey: identityKey) else {
            return false
        }
        guard snapshot.observedAt >= (account.rateLimitsObservedAt ?? .distantPast) else {
            return false
        }

        var didChange = RateLimitAccountUpdater.apply(snapshot, to: account)

        if let sevenDayDataStatusRaw = rateLimits?.sevenDayDataStatusRaw,
           account.sevenDayDataStatusRaw != sevenDayDataStatusRaw {
            account.sevenDayDataStatusRaw = sevenDayDataStatusRaw
            didChange = true
        }

        if let fiveHourDataStatusRaw = rateLimits?.fiveHourDataStatusRaw,
           account.fiveHourDataStatusRaw != fiveHourDataStatusRaw {
            account.fiveHourDataStatusRaw = fiveHourDataStatusRaw
            didChange = true
        }

        if let displayVersion = rateLimits?.displayVersion,
           account.rateLimitDisplayVersion != displayVersion {
            account.rateLimitDisplayVersion = displayVersion
            didChange = true
        }

        return didChange
    }

    private static func loadAccountArchive(from url: URL) throws -> CodexAccountArchive {
        try withSecurityScopedAccess(to: url) {
            let archiveData = try Data(contentsOf: url, options: .mappedIfSafe)
            return try CodexAccountArchive.decode(from: archiveData)
        }
    }

    private static func isAccountArchiveURL(_ url: URL) -> Bool {
        if let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
           contentType.isCodexAccountArchiveType {
            return true
        }

        return url.pathExtension.localizedCaseInsensitiveCompare("cxa") == .orderedSame
    }

    private static func withSecurityScopedAccess<T>(
        to url: URL,
        operation: () throws -> T
    ) throws -> T {
        let startedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if startedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return try operation()
    }

    private func presentAccountArchiveSavePanel(suggestedFilename: String) async -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.codexAccountArchive]
        panel.canCreateDirectories = true
        panel.canSelectHiddenExtension = true
        panel.isExtensionHidden = false
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        // Seed the save panel with the stem only. When a content type is also
        // configured, pre-populating the field with `.cxa` can cause AppKit to
        // append the archive extension a second time on save.
        panel.nameFieldStringValue = CodexAccountArchive.normalizedExportFilenameStem(from: suggestedFilename)

        let response: NSApplication.ModalResponse
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            response = await withCheckedContinuation { continuation in
                panel.beginSheetModal(for: window) { modalResponse in
                    continuation.resume(returning: modalResponse)
                }
            }
        } else {
            response = await withCheckedContinuation { continuation in
                panel.begin { modalResponse in
                    continuation.resume(returning: modalResponse)
                }
            }
        }

        guard response == .OK else {
            return nil
        }

        return panel.url.map(CodexAccountArchive.finalizedExportURL(from:))
    }

    private func waitForInitializationIfNeeded() async {
        let initializationTask = initializationTask
        await initializationTask?.value
    }

    private func performRefresh(showUnexpectedErrors: Bool) async {
        await waitForInitializationIfNeeded()
        await refreshAuthState(showUnexpectedErrors: showUnexpectedErrors)
        await refreshVisibleRateLimitsImmediatelyIfPossible()
    }

    private func startMonitoringIfNeeded() {
        guard !hasStartedMonitoring else {
            return
        }

        hasStartedMonitoring = true

        Task { [weak self] in
            guard let self else {
                return
            }

            await self.authFileManager.startMonitoring { [weak self] in
                guard let self else {
                    return
                }

                Task { @MainActor [weak self] in
                    guard let self else {
                        return
                    }

                    self.handleObservedAuthFileChange()
                }
            }
        }
    }

    private func handleObservedAuthFileChange() {
        observedAuthFileChangeTask?.cancel()
        observedAuthFileChangeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard let self else {
                return
            }

            await self.refreshAuthState(showUnexpectedErrors: false)
            await self.autoAddObservedAccountIfNeeded()
        }
    }

    private func autoAddObservedAccountIfNeeded() async {
        guard CodexSharedPreferences.automaticallyAddAccounts else {
            return
        }

        do {
            let readResult = try await authFileManager.readAuthFile()
            guard !readResult.contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }

            let snapshot = try await parseSnapshot(from: readResult.contents)
            let modelContext = try requireModelContext()
            let accounts = try fetchAccounts()

            if let match = accountMatch(for: snapshot, in: accounts) {
                _ = try await storeSnapshot(snapshot, on: match.account)
                _ = AccountAvailabilityUpdater.markAvailable(match.account)
                _ = await removeUnavailableReplacementDuplicates(
                    matching: snapshot,
                    keeping: match.account,
                    from: accounts,
                    in: modelContext
                )
                try modelContext.save()
                publishSharedState()
                requestImmediateRateLimitRefresh(for: snapshot.identityKey)
                return
            }

            try await addStoredAccount(
                from: snapshot,
                at: Date(),
                existingAccounts: accounts,
                in: modelContext
            )
            try modelContext.save()
            publishSharedState()
            requestImmediateRateLimitRefresh(for: snapshot.identityKey)
        } catch {
            logger.debug("Auto-add skipped after observed auth.json change: \(String(describing: error), privacy: .private)")
        }
    }

    func processPendingSharedCommands(
        allowsUnitTestExecution: Bool = false,
        queue: CodexSharedAppCommandQueue = CodexSharedAppCommandQueue(),
        resultStore: CodexSharedAppCommandResultStore = CodexSharedAppCommandResultStore()
    ) async {
        guard allowsUnitTestExecution || !Self.isRunningMainApplicationUnitTests else {
            return
        }

        await waitForInitializationIfNeeded()

        guard !isProcessingSharedCommands else {
            // Multiple distributed notifications can arrive while one pass is
            // already awaiting app-owned work. Record that we owe the queue
            // another pass instead of dropping the later signal on the floor.
            shouldProcessSharedCommandsAgain = true
            return
        }

        isProcessingSharedCommands = true
        defer {
            isProcessingSharedCommands = false
            shouldProcessSharedCommandsAgain = false
        }

        var shouldTerminateAfterDraining = false

        while true {
            shouldProcessSharedCommandsAgain = false

            let commands: [CodexSharedAppCommand]
            do {
                commands = try queue.load()
            } catch {
                logger.error("Couldn't load pending shared app commands: \(String(describing: error), privacy: .private)")
                return
            }

            guard !commands.isEmpty else {
                // A command can be enqueued after we observe an empty queue but
                // before this pass fully exits. In that edge case, an
                // in-flight wakeup request marks another pass as pending.
                guard !shouldProcessSharedCommandsAgain else {
                    continue
                }
                break
            }

            var acknowledgedAnyCommand = false
            var deferredAnyCommand = false

            for command in commands {
                let outcome = await handleSharedAppCommand(command)
                guard outcome.shouldAcknowledge else {
                    deferredAnyCommand = true
                    continue
                }

                if let result = outcome.result {
                    do {
                        // Intents wait on this shared result file, so persist
                        // the completion before dropping the durable queue item.
                        try resultStore.save(result)
                    } catch {
                        logger.error(
                            "Couldn't save shared app command result \(command.id.uuidString, privacy: .public): \(String(describing: error), privacy: .private)"
                        )
                        deferredAnyCommand = true
                        continue
                    }
                }

                acknowledgedAnyCommand = true
                do {
                    try queue.removeCommand(id: command.id)
                    if outcome.shouldTerminateAfterAcknowledgement {
                        shouldTerminateAfterDraining = true
                    }
                } catch {
                    logger.error(
                        "Couldn't acknowledge shared app command \(command.id.uuidString, privacy: .public): \(String(describing: error), privacy: .private)"
                    )
                }
            }

            // Leave deferred work queued for the next external wakeup instead
            // of spinning forever on commands this process cannot complete yet.
            if !acknowledgedAnyCommand && deferredAnyCommand && !shouldProcessSharedCommandsAgain {
                break
            }

            // Always re-check the persisted queue after each handled batch.
            // Commands can be appended while we are awaiting app-owned work,
            // and relying only on a separate wakeup signal can still strand
            // them if that signal is delayed or coalesced away.
        }

        if shouldTerminateAfterDraining {
            terminateApplication()
        }
    }

    /// Coalesce command-queue wakeups through one entrypoint so callers can
    /// safely request another pass without needing to know whether a pass is
    /// already active. If the processor is already running, this only marks
    /// that another queue scan is needed after the current pass finishes.
    func requestPendingSharedCommandsProcessing(
        allowsUnitTestExecution: Bool = false,
        queue: CodexSharedAppCommandQueue = CodexSharedAppCommandQueue(),
        resultStore: CodexSharedAppCommandResultStore = CodexSharedAppCommandResultStore()
    ) {
        if isProcessingSharedCommands {
            shouldProcessSharedCommandsAgain = true
            return
        }

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            await self.processPendingSharedCommands(
                allowsUnitTestExecution: allowsUnitTestExecution,
                queue: queue,
                resultStore: resultStore
            )
        }
    }

    private func startObservingSharedCommandsIfNeeded() {
        guard sharedCommandObserver == nil else {
            return
        }

        sharedCommandObserver = DistributedNotificationCenter.default().addObserver(
            forName: CodexSharedAppCommandSignal.didEnqueueCommandNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                self.requestPendingSharedCommandsProcessing()
            }
        }
    }

    private func startObservingPendingAccountOpenRequestsIfNeeded() {
        guard pendingAccountOpenObserver == nil else {
            return
        }

        pendingAccountOpenObserver = DistributedNotificationCenter.default().addObserver(
            forName: CodexPendingAccountOpenSignal.didRequestOpenAccountNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.consumePendingAccountOpenRequestIfNeeded()
            }
        }
    }

    private struct SharedAppCommandHandlingOutcome: Equatable {
        let shouldAcknowledge: Bool
        let shouldTerminateAfterAcknowledgement: Bool
        let result: CodexSharedAppCommandResult?

        static let handled = SharedAppCommandHandlingOutcome(
            shouldAcknowledge: true,
            shouldTerminateAfterAcknowledgement: false,
            result: nil
        )
        static let retryLater = SharedAppCommandHandlingOutcome(
            shouldAcknowledge: false,
            shouldTerminateAfterAcknowledgement: false,
            result: nil
        )
        static let handledAndTerminate = SharedAppCommandHandlingOutcome(
            shouldAcknowledge: true,
            shouldTerminateAfterAcknowledgement: true,
            result: nil
        )
    }

    private func handleSharedAppCommand(_ command: CodexSharedAppCommand) async -> SharedAppCommandHandlingOutcome {
        switch command.action {
        case .captureCurrentAccount:
            guard await captureCurrentAccountNow(allowsInteractiveRecovery: false) else {
                guard command.expectsResult else {
                    return .retryLater
                }

                return SharedAppCommandHandlingOutcome(
                    shouldAcknowledge: true,
                    shouldTerminateAfterAcknowledgement: false,
                    result: sharedCommandResult(
                        for: command,
                        status: .failure,
                        message: "Codex Switcher couldn't save the current account."
                    )
                )
            }

            let savedAccount = activeIdentityKey.flatMap { identityKey in
                try? fetchAccounts().first(where: { $0.identityKey == identityKey })
            }
            let message = savedAccount.map { "Saved \"\($0.name)\"." } ?? "Saved the current Codex account."
            return SharedAppCommandHandlingOutcome(
                shouldAcknowledge: true,
                shouldTerminateAfterAcknowledgement: false,
                result: sharedCommandResult(
                    for: command,
                    status: .success,
                    message: message,
                    accountIdentityKey: savedAccount?.identityKey ?? activeIdentityKey
                )
            )

        case .switchAccount:
            guard
                let identityKey = command.accountIdentityKey,
                !identityKey.isEmpty
            else {
                return SharedAppCommandHandlingOutcome(
                    shouldAcknowledge: true,
                    shouldTerminateAfterAcknowledgement: false,
                    result: sharedCommandResult(
                        for: command,
                        status: .failure,
                        message: "Codex Switcher couldn't determine which account to switch to."
                    )
                )
            }

            do {
                guard let account = try fetchAccounts().first(where: { $0.identityKey == identityKey }) else {
                    return SharedAppCommandHandlingOutcome(
                        shouldAcknowledge: true,
                        shouldTerminateAfterAcknowledgement: false,
                        result: sharedCommandResult(
                            for: command,
                            status: .failure,
                            message: "That Codex account no longer exists.",
                            accountIdentityKey: identityKey
                        )
                    )
                }

                guard hasLocalSnapshot(for: account) else {
                    return SharedAppCommandHandlingOutcome(
                        shouldAcknowledge: true,
                        shouldTerminateAfterAcknowledgement: false,
                        result: sharedCommandResult(
                            for: command,
                            status: .failure,
                            message: "That saved account needs a local capture on this Mac before it can be used.",
                            accountIdentityKey: identityKey
                        )
                    )
                }

                let previousIdentityKey = activeIdentityKey
                await switchToAccountNow(
                    id: account.id,
                    allowsInteractiveRecovery: false,
                    notificationKind: .userInitiated
                )

                guard activeIdentityKey == identityKey else {
                    return SharedAppCommandHandlingOutcome(
                        shouldAcknowledge: true,
                        shouldTerminateAfterAcknowledgement: false,
                        result: sharedCommandResult(
                            for: command,
                            status: .failure,
                            message: "Codex Switcher couldn't switch to \"\(account.name)\".",
                            accountIdentityKey: identityKey
                        )
                    )
                }

                let message = previousIdentityKey == identityKey
                    ? "Already using \"\(account.name)\"."
                    : "Now using \"\(account.name)\"."
                return SharedAppCommandHandlingOutcome(
                    shouldAcknowledge: true,
                    shouldTerminateAfterAcknowledgement: false,
                    result: sharedCommandResult(
                        for: command,
                        status: .success,
                        message: message,
                        accountIdentityKey: identityKey
                    )
                )
            } catch {
                logger.error(
                    "Couldn't switch shared-command account \(identityKey, privacy: .public): \(String(describing: error), privacy: .private)"
                )
                return SharedAppCommandHandlingOutcome(
                    shouldAcknowledge: true,
                    shouldTerminateAfterAcknowledgement: false,
                    result: sharedCommandResult(
                        for: command,
                        status: .failure,
                        message: "Codex Switcher couldn't switch to that account.",
                        accountIdentityKey: identityKey
                    )
                )
            }

        case .switchBestAccount:
            do {
                guard let account = bestAutopilotAccountCandidate(
                    from: try fetchAccounts().filter { !$0.identityKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                ) else {
                    return SharedAppCommandHandlingOutcome(
                        shouldAcknowledge: true,
                        shouldTerminateAfterAcknowledgement: false,
                        result: sharedCommandResult(
                            for: command,
                            status: .failure,
                            message: "No saved account currently has both 5h and 7d rate limits available for ranking."
                        )
                    )
                }

                let previousIdentityKey = activeIdentityKey
                await switchToAccountNow(
                    id: account.id,
                    allowsInteractiveRecovery: false,
                    notificationKind: .userInitiated
                )

                guard activeIdentityKey == account.identityKey else {
                    return SharedAppCommandHandlingOutcome(
                        shouldAcknowledge: true,
                        shouldTerminateAfterAcknowledgement: false,
                        result: sharedCommandResult(
                            for: command,
                            status: .failure,
                            message: "Codex Switcher couldn't switch to the best available account.",
                            accountIdentityKey: account.identityKey
                        )
                    )
                }

                let message = previousIdentityKey == account.identityKey
                    ? "Already using \"\(account.name)\", your best available account."
                    : "Now using \"\(account.name)\", your best available account."
                return SharedAppCommandHandlingOutcome(
                    shouldAcknowledge: true,
                    shouldTerminateAfterAcknowledgement: false,
                    result: sharedCommandResult(
                        for: command,
                        status: .success,
                        message: message,
                        accountIdentityKey: account.identityKey
                    )
                )
            } catch {
                logger.error("Couldn't switch to the best shared-command account: \(String(describing: error), privacy: .private)")
                return SharedAppCommandHandlingOutcome(
                    shouldAcknowledge: true,
                    shouldTerminateAfterAcknowledgement: false,
                    result: sharedCommandResult(
                        for: command,
                        status: .failure,
                        message: "Codex Switcher couldn't switch to the best available account."
                    )
                )
            }

        case .removeAccount:
            guard
                let identityKey = command.accountIdentityKey,
                !identityKey.isEmpty
            else {
                return SharedAppCommandHandlingOutcome(
                    shouldAcknowledge: true,
                    shouldTerminateAfterAcknowledgement: false,
                    result: sharedCommandResult(
                        for: command,
                        status: .failure,
                        message: "Codex Switcher couldn't determine which account to remove."
                    )
                )
            }

            do {
                guard let account = try fetchAccounts().first(where: { $0.identityKey == identityKey }) else {
                    return SharedAppCommandHandlingOutcome(
                        shouldAcknowledge: true,
                        shouldTerminateAfterAcknowledgement: false,
                        result: sharedCommandResult(
                            for: command,
                            status: .success,
                            message: "That Codex account was already removed.",
                            accountIdentityKey: identityKey
                        )
                    )
                }

                guard await removeAccountsNow(withIDs: [account.id], allowsInteractiveRecovery: false) else {
                    guard command.expectsResult else {
                        return .retryLater
                    }

                    return SharedAppCommandHandlingOutcome(
                        shouldAcknowledge: true,
                        shouldTerminateAfterAcknowledgement: false,
                        result: sharedCommandResult(
                            for: command,
                            status: .failure,
                            message: "Codex Switcher couldn't remove \"\(account.name)\".",
                            accountIdentityKey: identityKey
                        )
                    )
                }

                return SharedAppCommandHandlingOutcome(
                    shouldAcknowledge: true,
                    shouldTerminateAfterAcknowledgement: false,
                    result: sharedCommandResult(
                        for: command,
                        status: .success,
                        message: "Removed \"\(account.name)\".",
                        accountIdentityKey: identityKey
                    )
                )
            } catch {
                logger.error(
                    "Couldn't remove shared-command account \(identityKey, privacy: .public): \(String(describing: error), privacy: .private)"
                )

                guard command.expectsResult else {
                    return .retryLater
                }

                return SharedAppCommandHandlingOutcome(
                    shouldAcknowledge: true,
                    shouldTerminateAfterAcknowledgement: false,
                    result: sharedCommandResult(
                        for: command,
                        status: .failure,
                        message: "Codex Switcher couldn't remove that account.",
                        accountIdentityKey: identityKey
                    )
                )
            }

        case .quitApplication:
            switch command.quitRoutingDecision(
                currentProcess: .current,
                runningProcesses: runningMainApplicationProcesses()
            ) {
            case .terminateCurrentProcess:
                return .handledAndTerminate

            case .waitForTargetProcess:
                return .retryLater

            case .discardStaleCommand:
                return .handled
            }
        }
    }

    private func runningMainApplicationProcesses() -> [CodexSharedAppProcessIdentity] {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: CodexSharedApplicationIdentity.mainApplicationBundleIdentifier)
            .map(CodexSharedAppProcessIdentity.init(runningApplication:))
    }

    private func sharedCommandResult(
        for command: CodexSharedAppCommand,
        status: CodexSharedAppCommandResultStatus,
        message: String,
        accountIdentityKey: String? = nil
    ) -> CodexSharedAppCommandResult? {
        guard command.expectsResult else {
            return nil
        }

        return CodexSharedAppCommandResult(
            commandID: command.id,
            status: status,
            message: message,
            accountIdentityKey: accountIdentityKey
        )
    }

    private func startObservingRemoteSwitchesIfNeeded() {
        guard remoteSwitchObserver == nil else {
            return
        }

        remoteSwitchObserver = DistributedNotificationCenter.default().addObserver(
            forName: CodexSharedSwitchFeedback.didSwitchAccountNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let signal = CodexSharedSwitchFeedback.signal(from: notification) else {
                return
            }

            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                await self.handleRemoteSwitchSignal(signal)
            }
        }
    }

    private func startObservingSystemStateIfNeeded() {
        guard !hasStartedObservingSystemState else {
            return
        }

        hasStartedObservingSystemState = true
        isApplicationActive = NSApplication.shared.isActive
        let workspaceNotificationCenter = NSWorkspace.shared.notificationCenter
        codexDesktopAppObserver.refresh()
        workspaceLaunchObserver = workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleCodexRunningAppsChanged()
            }
        }
        workspaceTerminationObserver = workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleCodexRunningAppsChanged()
            }
        }
        systemStateObservationTasks = [
            Task { @MainActor [weak self] in
                for await _ in NotificationCenter.default.notifications(
                    named: NSApplication.didBecomeActiveNotification
                ) {
                    guard let self else {
                        return
                    }

                    self.setApplicationActive(true)
                }
            },
            Task { @MainActor [weak self] in
                for await _ in NotificationCenter.default.notifications(
                    named: NSApplication.didResignActiveNotification
                ) {
                    guard let self else {
                        return
                    }

                    self.setApplicationActive(false)
                }
            },
            Task { @MainActor [weak self] in
                for await _ in workspaceNotificationCenter.notifications(named: NSWorkspace.willSleepNotification) {
                    guard let self else {
                        return
                    }

                    self.isSystemSleeping = true
                }
            },
            Task { @MainActor [weak self] in
                for await _ in workspaceNotificationCenter.notifications(named: NSWorkspace.didWakeNotification) {
                    guard let self else {
                        return
                    }

                    self.isSystemSleeping = false
                    if self.isRateLimitSurfaceActive {
                        self.requestImmediateRateLimitRefreshForVisibleAccounts()
                    }
                    self.scheduleAutopilotEvaluationSoon(
                        after: Self.autopilotWakeDelay,
                        trigger: .systemWoke
                    )
                }
            },
            Task { @MainActor [weak self] in
                for await _ in workspaceNotificationCenter.notifications(named: NSWorkspace.screensDidSleepNotification) {
                    guard let self else {
                        return
                    }

                    self.areScreensSleeping = true
                }
            },
            Task { @MainActor [weak self] in
                for await _ in workspaceNotificationCenter.notifications(named: NSWorkspace.screensDidWakeNotification) {
                    guard let self else {
                        return
                    }

                    self.areScreensSleeping = false
                    if self.isRateLimitSurfaceActive {
                        self.requestImmediateRateLimitRefreshForVisibleAccounts()
                    }
                    self.scheduleAutopilotEvaluationSoon(
                        after: Self.autopilotWakeDelay,
                        trigger: .systemWoke
                    )
                }
            },
        ]
    }

    private func notePotentialPendingCodexRestart(for target: PendingCodexRestartBanner.Target) {
        codexDesktopAppObserver.refresh()
        let runningApps = codexDesktopAppObserver.runningApps
        guard !runningApps.isEmpty else {
            pendingCodexRestartBanner = nil
            return
        }

        pendingCodexRestartBanner = PendingCodexRestartBanner(
            target: target,
            shownAt: .now,
            codexProcessIDsAtSwitch: Set(runningApps.map(\.id))
        )
    }

    private func handleCodexRunningAppsChanged() {
        codexDesktopAppObserver.refresh()

        guard let banner = pendingCodexRestartBanner else {
            return
        }

        let currentPIDs = Set(codexDesktopAppObserver.runningApps.map(\.id))
        if banner.codexProcessIDsAtSwitch.isDisjoint(with: currentPIDs) {
            pendingCodexRestartBanner = nil
        }
    }

    func dismissPendingCodexRestartBanner() {
        pendingCodexRestartBanner = nil
    }

    private func scheduleAutopilotEvaluationSoon(
        after delay: TimeInterval = 0,
        trigger: AutopilotTrigger? = nil
    ) {
        guard isAutopilotEnabled else {
            return
        }

        if let trigger {
            pendingAutopilotImmediateTrigger = trigger
        }

        let candidateDate = Date().addingTimeInterval(max(delay, 0))

        if let nextAutopilotEvaluationAt {
            self.nextAutopilotEvaluationAt = min(nextAutopilotEvaluationAt, candidateDate)
        } else {
            nextAutopilotEvaluationAt = candidateDate
        }
    }

    private func updateAutopilotState() {
        guard hasConfiguredInitialState, isAutopilotEnabled else {
            autopilotTask?.cancel()
            autopilotTask = nil
            return
        }

        guard autopilotTask == nil else {
            return
        }

        if nextAutopilotEvaluationAt == nil {
            scheduleAutopilotEvaluationSoon(trigger: .started)
        }

        autopilotTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            await self.runAutopilotLoop()
        }
    }

    private var isAutopilotPausedBySystemState: Bool {
        isSystemSleeping || areScreensSleeping
    }

    private var currentAutopilotRefreshInterval: TimeInterval {
        Self.autopilotRefreshInterval
    }

    private var currentAutopilotTaskTriggeredMinimumGap: TimeInterval {
        Self.autopilotTaskTriggeredMinimumGap
    }

    private var isLowPowerModeEnabled: Bool {
        lowPowerModeProvider()
    }

    private var currentBatteryChargePercent: Int? {
        batteryChargePercentProvider()
    }

    private var isBatteryChargeCriticallyLow: Bool {
        guard let currentBatteryChargePercent else {
            return false
        }

        return currentBatteryChargePercent <= Self.batterySaverRefreshPauseThreshold
    }

    // Only background timers are paused by battery saver conditions. Explicit
    // user and system triggers still run immediately so the app feels current
    // when it becomes visible or when the user asks for a refresh.
    private var shouldPausePeriodicRefreshTimersForPowerSaving: Bool {
        isLowPowerModeEnabled || isBatteryChargeCriticallyLow
    }

    private func runAutopilotLoop() async {
        defer {
            autopilotTask = nil
        }

        while isAutopilotEnabled, !Task.isCancelled {
            if !isAutopilotPausedBySystemState {
                await observeRecentSessionActivityIfNeeded()

                if let trigger = autopilotTriggerDue(relativeTo: Date()) {
                    await runAutopilotEvaluation(trigger: trigger)
                }
            }

            try? await Task.sleep(for: Self.autopilotLoopCadence)
        }
    }

    private func observeRecentSessionActivityIfNeeded() async {
        guard activeIdentityKey != nil else {
            return
        }

        guard let linkedLocation = try? await authFileManager.linkedLocation() else {
            return
        }

        guard linkedLocation.credentialStoreHint.isSupportedForFileSwitching else {
            return
        }

        guard let observation = await sessionRateLimitReader.readLatestObservation(
            in: linkedLocation.folderURL
        ) else {
            return
        }

        let latestKnownActivityAt = lastObservedSessionActivityAt ?? .distantPast
        guard observation.observedAt > latestKnownActivityAt else {
            return
        }

        lastObservedSessionActivityAt = observation.observedAt
        scheduleAutopilotEvaluationAfterRecentSessionActivity(observedAt: observation.observedAt)
    }

    private func scheduleAutopilotEvaluationAfterRecentSessionActivity(observedAt: Date) {
        // Codex can emit several session updates while a task is still running.
        // Wait for a short quiet period before reevaluating so background
        // switching reacts after a task finishes rather than during it.
        let quietDelay = max(
            Self.autopilotSessionQuietWindow - Date().timeIntervalSince(observedAt),
            0
        )
        scheduleAutopilotEvaluationSoon(after: quietDelay)
    }

    private func autopilotTriggerDue(relativeTo now: Date) -> AutopilotTrigger? {
        guard !isAutopilotPausedBySystemState else {
            return nil
        }

        if let pendingAutopilotImmediateTrigger,
           let nextAutopilotEvaluationAt,
           now >= nextAutopilotEvaluationAt {
            return pendingAutopilotImmediateTrigger
        }

        if let lastObservedSessionActivityAt,
           lastHandledSessionActivityAt != lastObservedSessionActivityAt,
           now.timeIntervalSince(lastObservedSessionActivityAt) >= Self.autopilotSessionQuietWindow,
           now.timeIntervalSince(lastAutopilotEvaluationAt ?? .distantPast) >= currentAutopilotTaskTriggeredMinimumGap {
            return .sessionBecameQuiet
        }

        if shouldPausePeriodicRefreshTimersForPowerSaving {
            return nil
        }

        guard let nextAutopilotEvaluationAt, now >= nextAutopilotEvaluationAt else {
            return nil
        }

        if let lastObservedSessionActivityAt,
           now.timeIntervalSince(lastObservedSessionActivityAt) < Self.autopilotSessionQuietWindow {
            return nil
        }

        return .scheduled
    }

    private func runAutopilotEvaluation(trigger: AutopilotTrigger) async {
        await waitForInitializationIfNeeded()

        guard !Task.isCancelled else {
            return
        }

        if isAutopilotPausedBySystemState {
            return
        }

        if isSwitching {
            scheduleAutopilotEvaluationSoon(
                after: 30,
                trigger: trigger.shouldPreserveImmediatePriorityWhenDeferred ? trigger : nil
            )
            return
        }

        await refreshAuthState(showUnexpectedErrors: false)
        applyLocalRateLimitResetsIfNeeded(relativeTo: Date())
        let clearsPendingImmediateTrigger = pendingAutopilotImmediateTrigger == trigger

        defer {
            let completionDate = Date()

            if trigger == .sessionBecameQuiet {
                lastHandledSessionActivityAt = lastObservedSessionActivityAt
            }

            if clearsPendingImmediateTrigger {
                pendingAutopilotImmediateTrigger = nil
            }

            lastAutopilotEvaluationAt = completionDate

            if trigger != .testing {
                nextAutopilotEvaluationAt = completionDate.addingTimeInterval(currentAutopilotRefreshInterval)
            }
        }

        guard canAutopilotAttemptBackgroundSwitch else {
            return
        }

        do {
            let accounts = try fetchAccounts()
                .filter { !$0.identityKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

            guard !accounts.isEmpty else {
                return
            }

            await refreshAutopilotRateLimits(
                for: orderedAccountsForAutopilotRefresh(from: accounts),
                relativeTo: Date(),
                trigger: trigger
            )

            let refreshedAccounts = try fetchAccounts()
                .filter { !$0.identityKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

            guard let bestCandidate = bestAutopilotAccountCandidate(from: refreshedAccounts) else {
                return
            }

            guard bestCandidate.identityKey != activeIdentityKey else {
                return
            }

            await switchToAccountNow(
                id: bestCandidate.id,
                allowsInteractiveRecovery: false,
                notificationKind: .recoveryAttention
            )
        } catch {
            logger.error("Autopilot evaluation failed: \(String(describing: error), privacy: .private)")
        }
    }

    private var canAutopilotAttemptBackgroundSwitch: Bool {
        switch authAccessState {
        case .ready, .missingAuthFile, .corruptAuthFile:
            true
        case .unlinked, .locationUnavailable, .accessDenied, .unsupportedCredentialStore:
            false
        }
    }

    private func refreshAutopilotRateLimits(
        for accounts: [StoredAccount],
        relativeTo now: Date,
        trigger: AutopilotTrigger
    ) async {
        for account in accounts {
            let shouldForceRefresh = trigger.forcesImmediateRateLimitRefresh
                || (trigger == .sessionBecameQuiet && account.identityKey == activeIdentityKey)

            guard shouldForceRefresh || shouldRefreshAutopilotRateLimits(for: account.identityKey, relativeTo: now) else {
                continue
            }

            await refreshRateLimitsNow(for: account.identityKey)
        }
    }

    private func shouldRefreshAutopilotRateLimits(for identityKey: String, relativeTo now: Date) -> Bool {
        if pendingForcedRateLimitRefreshes.contains(identityKey) {
            return true
        }

        if let backoffUntil = rateLimitFailureBackoffUntil[identityKey], backoffUntil > now {
            return false
        }

        if let snapshot = rateLimitSnapshotsByIdentityKey[identityKey] {
            if let nextResetAt = snapshot.nextResetAt, now >= nextResetAt {
                return true
            }

            return now.timeIntervalSince(snapshot.fetchedAt) >= currentAutopilotRefreshInterval
        }

        do {
            if let account = try fetchAccounts().first(where: { $0.identityKey == identityKey }),
               let observedAt = account.rateLimitsObservedAt {
                return now.timeIntervalSince(observedAt) >= currentAutopilotRefreshInterval
            }
        } catch {
            return true
        }

        return true
    }

    private func orderedAccountsForAutopilotRefresh(from accounts: [StoredAccount]) -> [StoredAccount] {
        var prioritizedAccounts = AccountsPresentationLogic.sortedAccounts(
            from: accounts.filter { hasLocalSnapshot(for: $0) && !$0.isUnavailable },
            sortCriterion: .rateLimit,
            sortDirection: .descending
        )

        guard let activeIdentityKey,
              let activeAccountIndex = prioritizedAccounts.firstIndex(where: { $0.identityKey == activeIdentityKey }) else {
            return prioritizedAccounts
        }

        let activeAccount = prioritizedAccounts.remove(at: activeAccountIndex)
        prioritizedAccounts.insert(activeAccount, at: 0)
        return prioritizedAccounts
    }

    private func bestAutopilotAccountCandidate(from accounts: [StoredAccount]) -> StoredAccount? {
        AccountsPresentationLogic.sortedAccounts(
            from: accounts.filter { hasLocalSnapshot(for: $0) && !$0.isUnavailable },
            sortCriterion: .rateLimit,
            sortDirection: .descending
        )
        .first { $0.fiveHourLimitUsedPercent != nil && $0.sevenDayLimitUsedPercent != nil }
    }

    private func handleRemoteSwitchSignal(_ signal: CodexSharedSwitchSignal) async {
        await waitForInitializationIfNeeded()
        await refreshAuthState(showUnexpectedErrors: false)

        do {
            if let switchedAccount = try fetchAccounts().first(where: { $0.identityKey == signal.identityKey }) {
                selection = [switchedAccount.id]
                renameTargetID = nil
                persistSuccessfulLoginMetadata(
                    for: switchedAccount,
                    at: Date(),
                    in: try requireModelContext(),
                    allowsInteractiveRecovery: false,
                    partialSuccessTitle: "Account Switched"
                )
                publishSharedState()
            }
        } catch {
            logger.error(
                "Couldn't apply remote account switch selection for \(signal.identityKey, privacy: .public): \(String(describing: error), privacy: .private)"
            )
        }

        // The intent path already delivers its own confirmation. Refresh the
        // app state here without posting a second banner from the app process.
        requestImmediateRateLimitRefresh(for: signal.identityKey)
    }

    private func persistSuccessfulLoginMetadata(
        for account: StoredAccount,
        at lastLoginAt: Date,
        in modelContext: ModelContext,
        allowsInteractiveRecovery: Bool,
        partialSuccessTitle: String
    ) {
        let didUpdateLastLogin = StoredAccountMutations.applyLastLogin(lastLoginAt, to: account)
        let normalizedLegacyFields = account.normalizeLegacyLocalOnlyFields()
        guard didUpdateLastLogin || normalizedLegacyFields else {
            return
        }

        do {
            try modelContext.save()
        } catch {
            if allowsInteractiveRecovery {
                present(
                    UserFacingAlert(
                        title: partialSuccessTitle,
                        message: "The Codex account is active, but the local last-login update failed: \(error.localizedDescription)"
                    )
                )
            } else {
                logger.error("Account last-login update failed after a successful switch: \(String(describing: error), privacy: .private)")
            }
        }
    }

    private func finishLocationImport(_ result: Result<[URL], any Error>) async {
        switch result {
        case let .success(urls):
            guard let selectedURL = urls.first else {
                pendingLocationAction = nil
                return
            }

            do {
                _ = try await authFileManager.linkLocation(selectedURL)
                let pendingAction = pendingLocationAction
                pendingLocationAction = nil
                await refreshAuthState(showUnexpectedErrors: false)
                await retryPendingLocationActionIfNeeded(pendingAction)
            } catch {
                pendingLocationAction = nil
                present(error, title: "Couldn't Link Codex Folder")
            }

        case let .failure(error):
            pendingLocationAction = nil
            guard !Self.shouldSilentlyDismiss(error) else {
                return
            }

            present(error, title: "Couldn't Link Codex Folder")
        }
    }

    private func retryPendingLocationActionIfNeeded(_ pendingLocationAction: PendingLocationAction?) async {
        guard let pendingLocationAction else {
            return
        }

        switch pendingLocationAction {
        case .captureCurrentAccount:
            await captureCurrentAccountNow()
        case let .switchAccount(accountID):
            if accountID == Self.noneAccountSelectionID {
                switchToNone()
            } else {
                await switchToAccountNow(id: accountID)
            }
        case .refresh:
            await performRefresh(showUnexpectedErrors: true)
        }
    }

    private func reconcileStoredSnapshotsIfNeeded() async {
        do {
            let accounts = try fetchAccounts()
            var didChange = false

            for account in accounts {
                didChange = await migrateLegacySnapshotIfNeeded(for: account) || didChange

                guard let storedContents = await bestAvailableSnapshotContents(for: account) else {
                    continue
                }

                do {
                    let snapshot = try await parseSnapshot(from: storedContents)
                    didChange = (try await storeSnapshot(
                        snapshot,
                        on: account,
                        updatesAvailability: false
                    )) || didChange
                } catch {
                    logger.error("Stored snapshot reconciliation failed for account \(account.id.uuidString, privacy: .public): \(String(describing: error), privacy: .private)")
                }
            }

            didChange = await reconcileDuplicateAccountsIfNeeded() || didChange

            if didChange {
                try requireModelContext().save()
            }
        } catch {
            present(error, title: "Couldn't Upgrade Saved Accounts")
        }
    }

    private func reconcileSharedLastLoginUpdatesIfNeeded() {
        do {
            _ = try StoredAccountMutations.applySharedLastLoginUpdates(
                in: try requireModelContext()
            )
        } catch {
            logger.error("Shared last-login reconciliation failed: \(String(describing: error), privacy: .private)")
        }
    }

    private func reconcileDisplayOnlyFieldsIfNeeded() {
        do {
            var didChange = false

            for account in try fetchAccounts() {
                if account.iconSystemName.isEmpty {
                    account.iconSystemName = AccountIconOption.defaultOption.systemName
                    didChange = true
                }

                if account.rateLimitDisplayVersion != RateLimitAccountUpdater.currentDisplayVersion {
                    if let sevenDayUsedPercent = account.sevenDayLimitUsedPercent {
                        account.sevenDayLimitUsedPercent = 100 - min(max(sevenDayUsedPercent, 0), 100)
                        didChange = true
                    }

                    if let fiveHourUsedPercent = account.fiveHourLimitUsedPercent {
                        account.fiveHourLimitUsedPercent = 100 - min(max(fiveHourUsedPercent, 0), 100)
                        didChange = true
                    }

                    account.rateLimitDisplayVersion = RateLimitAccountUpdater.currentDisplayVersion
                    didChange = true
                }
            }

            if didChange {
                try requireModelContext().save()
            }
        } catch {
            present(error, title: "Couldn't Refresh Saved Accounts")
        }
    }

    private func refreshAuthState(showUnexpectedErrors: Bool) async {
        defer { publishSharedState() }

        let linkedLocation: AuthLinkedLocation
        do {
            guard let resolvedLinkedLocation = try await authFileManager.linkedLocation() else {
                activeIdentityKey = nil
                authAccessState = .unlinked
                return
            }

            linkedLocation = resolvedLinkedLocation
        } catch let error as AuthFileAccessError {
            activeIdentityKey = nil
            applyAuthAccessState(error, linkedLocation: nil)
            return
        } catch {
            activeIdentityKey = nil
            authAccessState = .unlinked
            return
        }

        if !linkedLocation.credentialStoreHint.isSupportedForFileSwitching {
            activeIdentityKey = nil
            authAccessState = .unsupportedCredentialStore(
                linkedFolder: linkedLocation.folderURL,
                mode: linkedLocation.credentialStoreHint
            )
            return
        }

        let liveReadResult: AuthFileReadResult
        let liveSnapshot: CodexAuthSnapshot
        do {
            liveReadResult = try await authFileManager.readAuthFile()
            liveSnapshot = try await parseSnapshot(from: liveReadResult.contents)
        } catch let error as AuthFileAccessError {
            activeIdentityKey = nil
            applyAuthAccessState(error, linkedLocation: linkedLocation)

            if showUnexpectedErrors, Self.shouldPresentUnexpectedAuthAlert(for: error) {
                present(error, title: "Couldn't Read Codex Auth File")
            }
            return
        } catch let error as CodexAuthFileError {
            activeIdentityKey = nil
            authAccessState = .corruptAuthFile(linkedFolder: linkedLocation.folderURL)

            if showUnexpectedErrors {
                present(error, title: "Couldn't Read Codex Auth File")
            }
            return
        } catch {
            activeIdentityKey = nil

            if showUnexpectedErrors {
                present(error, title: "Couldn't Read Codex Auth File")
            }
            return
        }

        activeIdentityKey = liveSnapshot.identityKey
        authAccessState = .ready(linkedFolder: linkedLocation.folderURL)

        do {
            try await refreshStoredAccountIfKnown(from: liveSnapshot, authFileURL: liveReadResult.url)
        } catch {
            logger.error("Live snapshot cache refresh failed: \(String(describing: error), privacy: .private)")
        }

        requestImmediateRateLimitRefresh(for: liveSnapshot.identityKey)
    }

    private func preserveCurrentLiveSnapshotIfKnown() async {
        do {
            let readResult = try await authFileManager.readAuthFile()
            let snapshot = try await parseSnapshot(from: readResult.contents)
            try await refreshStoredAccountIfKnown(from: snapshot, authFileURL: readResult.url)
            requestImmediateRateLimitRefresh(for: snapshot.identityKey)
        } catch let error as AuthFileAccessError {
            switch error {
            case .missingAuthFile, .accessRequired, .locationUnavailable, .accessDenied, .unsupportedCredentialStore:
                return
            case .invalidSelection, .cancelled, .unreadable, .unwritable, .verificationFailed:
                return
            }
        } catch {
            return
        }
    }

    private func refreshStoredAccountIfKnown(from snapshot: CodexAuthSnapshot, authFileURL: URL) async throws {
        guard let existingAccount = try fetchAccounts().first(where: { $0.identityKey == snapshot.identityKey }) else {
            return
        }

        let didChange = try await storeSnapshot(snapshot, on: existingAccount)
        let availabilityChanged = AccountAvailabilityUpdater.markAvailable(existingAccount)
        if didChange || availabilityChanged {
            try requireModelContext().save()
        }
    }

    private func loadStoredSnapshot(for account: StoredAccount) async throws -> String {
        let didChange = await migrateLegacySnapshotIfNeeded(for: account)
        if didChange {
            try? requireModelContext().save()
            publishSharedState()
        }

        let contents = try await secretStore.loadSnapshot(forIdentityKey: account.identityKey)
        let normalizedContents = try CodexAuthSnapshotNormalizer.normalizedForCodexRuntime(contents)

        if normalizedContents != contents {
            try await secretStore.saveSnapshot(normalizedContents, forIdentityKey: account.identityKey)
            _ = await exportSyncedRateLimitCredentialIfNeeded(
                from: normalizedContents,
                expectedIdentityKey: account.identityKey,
                excludingAccountIDsForDelete: [account.id]
            )
        }

        return normalizedContents
    }

    private func handleExpectedAuthOperationError(
        _ error: Error,
        title: String,
        retryAction: PendingLocationAction,
        allowsInteractiveRecovery: Bool = true
    ) async {
        if let authError = error as? AuthFileAccessError {
            switch authError {
            case .accessRequired, .accessDenied, .locationUnavailable:
                await refreshAuthState(showUnexpectedErrors: false)

                guard allowsInteractiveRecovery else {
                    return
                }

                pendingLocationAction = retryAction
                presentCodexFolderPicker()
                return

            case .missingAuthFile, .unsupportedCredentialStore:
                await refreshAuthState(showUnexpectedErrors: false)
                return

            case .cancelled:
                return

            case .invalidSelection, .unreadable, .unwritable, .verificationFailed:
                break
            }
        }

        if error is CodexAuthFileError {
            await refreshAuthState(showUnexpectedErrors: false)
        }

        guard allowsInteractiveRecovery else {
            logger.error("\(title, privacy: .public): \(String(describing: error), privacy: .private)")
            return
        }

        present(error, title: title)
    }

    private func handleCaptureCurrentAccountError(
        _ error: Error,
        title: String,
        allowsInteractiveRecovery: Bool = true
    ) async {
        if let authError = error as? AuthFileAccessError {
            await refreshAuthState(showUnexpectedErrors: false)

            guard allowsInteractiveRecovery else {
                logger.error("\(title, privacy: .public): \(String(describing: error), privacy: .private)")
                return
            }

            guard !authError.isUserCancellation else {
                return
            }

            present(error, title: title)
            return
        }

        if error is CodexAuthFileError {
            await refreshAuthState(showUnexpectedErrors: false)
        }

        guard allowsInteractiveRecovery else {
            logger.error("\(title, privacy: .public): \(String(describing: error), privacy: .private)")
            return
        }

        present(error, title: title)
    }

    private func applyAuthAccessState(_ error: AuthFileAccessError, linkedLocation: AuthLinkedLocation?) {
        switch error {
        case .accessRequired:
            authAccessState = .unlinked
        case let .missingAuthFile(_, credentialStoreHint):
            guard let linkedLocation else {
                authAccessState = .unlinked
                return
            }
            authAccessState = .missingAuthFile(
                linkedFolder: linkedLocation.folderURL,
                credentialStoreHint: credentialStoreHint
            )
        case let .locationUnavailable(url):
            authAccessState = .locationUnavailable(linkedFolder: url)
        case let .accessDenied(url):
            authAccessState = .accessDenied(linkedFolder: url)
        case let .unsupportedCredentialStore(url, mode):
            authAccessState = .unsupportedCredentialStore(linkedFolder: url, mode: mode)
        case .invalidSelection, .cancelled, .unreadable, .unwritable, .verificationFailed:
            if let linkedLocation {
                authAccessState = .ready(linkedFolder: linkedLocation.folderURL)
            } else {
                authAccessState = .unlinked
            }
        }
    }

    @discardableResult
    private func update(account: StoredAccount, from snapshot: CodexAuthSnapshot) -> Bool {
        var didChange = account.normalizeLegacyLocalOnlyFields()

        if account.identityKey != snapshot.identityKey {
            account.identityKey = snapshot.identityKey
            didChange = true
        }

        if account.authModeRaw != snapshot.authMode.rawValue {
            account.authModeRaw = snapshot.authMode.rawValue
            didChange = true
        }

        if account.emailHint != snapshot.email {
            account.emailHint = snapshot.email
            didChange = true
        }

        if account.accountIdentifier != snapshot.accountIdentifier {
            account.accountIdentifier = snapshot.accountIdentifier
            didChange = true
        }

        if account.iconSystemName.isEmpty {
            account.iconSystemName = AccountIconOption.defaultOption.systemName
            didChange = true
        }

        return didChange
    }

    private func migrateLegacySnapshotIfNeeded(for account: StoredAccount) async -> Bool {
        var didChange = false
        let previousIdentityKey = account.identityKey

        if let syncedContents = account.authFileContents, !syncedContents.isEmpty {
            do {
                let migratedSnapshot = try await parseSnapshot(from: syncedContents)
                didChange = update(account: account, from: migratedSnapshot) || didChange
                try await secretStore.saveSnapshot(
                    syncedContents,
                    forIdentityKey: migratedSnapshot.identityKey
                )
                _ = await exportSyncedRateLimitCredentialIfNeeded(
                    from: syncedContents,
                    expectedIdentityKey: migratedSnapshot.identityKey,
                    excludingAccountIDsForDelete: [account.id]
                )
                account.authFileContents = nil
                didChange = true

                let normalizedPreviousIdentityKey = previousIdentityKey.trimmingCharacters(in: .whitespacesAndNewlines)
                if normalizedPreviousIdentityKey != migratedSnapshot.identityKey,
                   !normalizedPreviousIdentityKey.isEmpty,
                   let modelContext = try? requireModelContext() {
                    await StoredAccountCloudSyncSupport.deleteArtifactsIfUnused(
                        identityKey: normalizedPreviousIdentityKey,
                        in: modelContext,
                        snapshotStore: secretStore,
                        syncedRateLimitCredentialStore: syncedRateLimitCredentialStore,
                        excludingAccountIDs: [account.id],
                        logger: logger
                    )
                }
            } catch {
                logger.error(
                    "Couldn't migrate synced snapshot for account \(account.id.uuidString, privacy: .public): \(String(describing: error), privacy: .private)"
                )
            }
        }

        let normalizedIdentityKey = account.identityKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedIdentityKey.isEmpty {
            do {
                if try await secretStore.migrateLegacySnapshotIfNeeded(
                    fromLegacyAccountID: account.id,
                    toIdentityKey: normalizedIdentityKey
                ) {
                    if let migratedContents = try? await secretStore.loadSnapshot(forIdentityKey: normalizedIdentityKey) {
                        _ = await exportSyncedRateLimitCredentialIfNeeded(
                            from: migratedContents,
                            expectedIdentityKey: normalizedIdentityKey,
                            excludingAccountIDsForDelete: [account.id]
                        )
                    }
                    didChange = true
                }
            } catch {
                logger.error(
                    "Couldn't migrate legacy keychain snapshot for account \(account.id.uuidString, privacy: .public): \(String(describing: error), privacy: .private)"
                )
            }
        }

        return didChange
    }

    private func bestAvailableSnapshotContents(for account: StoredAccount) async -> String? {
        _ = await migrateLegacySnapshotIfNeeded(for: account)

        do {
            return try await secretStore.loadSnapshot(forIdentityKey: account.identityKey)
        } catch AccountSnapshotStoreError.missingSnapshot {
            return nil
        } catch {
            logger.error(
                "Couldn't load local snapshot for account \(account.id.uuidString, privacy: .public): \(String(describing: error), privacy: .private)"
            )
            return nil
        }
    }

    private func bestAvailableRateLimitCredentials(for account: StoredAccount) async -> CodexRateLimitCredentials? {
        guard let snapshotContents = await bestAvailableSnapshotContents(for: account) else {
            return nil
        }

        do {
            return try CodexAuthFile.parseRateLimitCredentials(contents: snapshotContents)
        } catch {
            logger.error(
                "Couldn't parse rate-limit credentials for account \(account.id.uuidString, privacy: .public): \(String(describing: error), privacy: .private)"
            )
            return nil
        }
    }

    @discardableResult
    private func exportSyncedRateLimitCredentialIfNeeded(
        from rawContents: String,
        expectedIdentityKey: String,
        excludingAccountIDsForDelete: Set<UUID> = []
    ) async -> Bool {
        let normalizedIdentityKey = expectedIdentityKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedIdentityKey.isEmpty else {
            return false
        }

        guard let modelContext = try? requireModelContext() else {
            return false
        }

        let didExport = await StoredAccountCloudSyncSupport.exportSyncedRateLimitCredentialIfNeeded(
            from: rawContents,
            expectedIdentityKey: normalizedIdentityKey,
            in: modelContext,
            syncedRateLimitCredentialStore: syncedRateLimitCredentialStore,
            excludingAccountIDsForDelete: excludingAccountIDsForDelete,
            forceRewrite: StoredAccountCloudSyncSupport.shouldForceRewriteSyncedRateLimitCredential(
                for: normalizedIdentityKey
            ),
            logger: logger
        )

        if didExport {
            StoredAccountCloudSyncSupport.markSyncedRateLimitCredentialAccessibilityMigrated(
                for: normalizedIdentityKey
            )
        } else if let snapshot = try? CodexAuthFile.parse(contents: rawContents), snapshot.authMode == .apiKey {
            StoredAccountCloudSyncSupport.markSyncedRateLimitCredentialAccessibilityMigrated(
                for: normalizedIdentityKey
            )
        }

        return didExport
    }

    private func saveImportedRateLimitCredentialIfUsable(
        _ credential: SyncedRateLimitCredential?,
        expectedIdentityKey: String
    ) async -> Bool {
        guard let credential else {
            return false
        }

        let normalizedExpectedIdentityKey = expectedIdentityKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedExpectedIdentityKey.isEmpty,
              credential.identityKey == normalizedExpectedIdentityKey,
              credential.rateLimitCredentials.authMode != .apiKey,
              credential.rateLimitCredentials.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return false
        }

        do {
            if let existingCredential = try? await syncedRateLimitCredentialStore.load(
                forIdentityKey: normalizedExpectedIdentityKey
            ), existingCredential.exportedAt >= credential.exportedAt {
                return true
            }

            try await syncedRateLimitCredentialStore.save(credential)
            return true
        } catch {
            logger.error(
                "Couldn't save imported synced rate-limit credential for \(normalizedExpectedIdentityKey, privacy: .private): \(String(describing: error), privacy: .private)"
            )
            return false
        }
    }

    private func storeSnapshot(
        _ snapshot: CodexAuthSnapshot,
        rateLimitObservation: CodexRateLimitObservation? = nil,
        importedRateLimitCredential: SyncedRateLimitCredential? = nil,
        on account: StoredAccount,
        updatesAvailability: Bool = true
    ) async throws -> Bool {
        let modelContext = try requireModelContext()
        let previousIdentityKey = account.identityKey
        let metadataChanged = update(account: account, from: snapshot)
        let availabilityChanged = updatesAvailability
            ? AccountAvailabilityUpdater.markAvailable(account)
            : false
        let rateLimitsChanged = rateLimitObservation.map {
            RateLimitAccountUpdater.apply($0, identityKey: snapshot.identityKey, to: account)
        } ?? false
        let normalizedContents = try CodexAuthSnapshotNormalizer
            .normalizedForCodexRuntime(snapshot.rawContents)
        let existingContents = try? await secretStore.loadSnapshot(forIdentityKey: account.identityKey)
        let needsSnapshotWrite = existingContents != normalizedContents

        if needsSnapshotWrite {
            try await secretStore.saveSnapshot(normalizedContents, forIdentityKey: account.identityKey)
        }

        if await saveImportedRateLimitCredentialIfUsable(
            importedRateLimitCredential,
            expectedIdentityKey: snapshot.identityKey
        ) {
            StoredAccountCloudSyncSupport.markSyncedRateLimitCredentialAccessibilityMigrated(
                for: snapshot.identityKey
            )
        } else {
            _ = await exportSyncedRateLimitCredentialIfNeeded(
                from: normalizedContents,
                expectedIdentityKey: snapshot.identityKey,
                excludingAccountIDsForDelete: [account.id]
            )
        }

        if previousIdentityKey != snapshot.identityKey,
           previousIdentityKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            await StoredAccountCloudSyncSupport.deleteArtifactsIfUnused(
                identityKey: previousIdentityKey,
                in: modelContext,
                snapshotStore: secretStore,
                syncedRateLimitCredentialStore: syncedRateLimitCredentialStore,
                excludingAccountIDs: [account.id],
                logger: logger
            )
        }

        var didChange = metadataChanged || availabilityChanged || rateLimitsChanged || needsSnapshotWrite
        if account.authFileContents != nil {
            account.authFileContents = nil
            didChange = true
        }

        return didChange
    }

    private var isRateLimitSurfaceActive: Bool {
        isApplicationActive || isMenuBarPresented
    }

    private func requestImmediateRateLimitRefresh(for identityKey: String) {
        requestImmediateRateLimitRefresh(for: [identityKey])
    }

    private func requestImmediateRateLimitRefreshForVisibleAccounts() {
        requestImmediateRateLimitRefresh(for: visibleRateLimitRefreshIdentityKeys())
    }

    // Manual and user-driven refresh triggers should bypass the normal polling
    // window and any temporary failure backoff, but still coalesce per-account
    // work so repeated focus/open events do not fan out into duplicate requests.
    private func requestImmediateRateLimitRefresh(for identityKeys: [String]) {
        let identities = normalizedRateLimitIdentityKeys(identityKeys)
        guard !identities.isEmpty else {
            return
        }

        for identityKey in identities {
            pendingForcedRateLimitRefreshes.insert(identityKey)
            rateLimitFailureBackoffUntil.removeValue(forKey: identityKey)
        }

        updateRateLimitPollingState()

        guard isRateLimitSurfaceActive else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            await self.refreshRateLimitsImmediately(for: identities)
        }
    }

    private func normalizedRateLimitIdentityKeys(_ identityKeys: [String]) -> [String] {
        var normalized: [String] = []
        var seen = Set<String>()

        for identityKey in identityKeys {
            let trimmedIdentityKey = identityKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedIdentityKey.isEmpty, !seen.contains(trimmedIdentityKey) else {
                continue
            }

            normalized.append(trimmedIdentityKey)
            seen.insert(trimmedIdentityKey)
        }

        return normalized
    }

    private func refreshRateLimitsImmediately(for identityKeys: [String]) async {
        for identityKey in normalizedRateLimitIdentityKeys(identityKeys) {
            await refreshRateLimitsNow(for: identityKey)
        }
    }

    private func visibleRateLimitRefreshIdentityKeys() -> [String] {
        var identities: [String] = []
        var seen = Set<String>()

        if let activeIdentityKey, !activeIdentityKey.isEmpty {
            identities.append(activeIdentityKey)
            seen.insert(activeIdentityKey)
        }

        for identityKey in visibleRateLimitIdentityCounts.keys.sorted() where !identityKey.isEmpty && !seen.contains(identityKey) {
            identities.append(identityKey)
            seen.insert(identityKey)
        }

        return identities
    }

    private func refreshVisibleRateLimitsImmediatelyIfPossible() async {
        let identities = visibleRateLimitRefreshIdentityKeys()
        guard !identities.isEmpty else {
            return
        }

        for identityKey in identities {
            pendingForcedRateLimitRefreshes.insert(identityKey)
            rateLimitFailureBackoffUntil.removeValue(forKey: identityKey)
        }

        updateRateLimitPollingState()

        guard isRateLimitSurfaceActive else {
            return
        }

        await refreshRateLimitsImmediately(for: identities)
    }

    private func updateRateLimitPollingState() {
        guard isRateLimitSurfaceActive, !rateLimitCandidateIdentityKeys().isEmpty else {
            rateLimitPollingTask?.cancel()
            rateLimitPollingTask = nil
            return
        }

        guard rateLimitPollingTask == nil else {
            return
        }

        rateLimitPollingTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            await self.runRateLimitPollingLoop()
        }
    }

    // Poll only while the user can currently see the app or its menu bar
    // window. The actual request spacing is enforced lower down by the rate-
    // limit provider's request limiter.
    private func runRateLimitPollingLoop() async {
        defer {
            rateLimitPollingTask = nil
        }

        while isRateLimitSurfaceActive, !Task.isCancelled {
            await refreshDueRateLimitsIfNeeded()

            if !isRateLimitSurfaceActive {
                break
            }

            try? await Task.sleep(for: Self.rateLimitPollingCadence)
        }
    }

    private func refreshDueRateLimitsIfNeeded() async {
        guard isRateLimitSurfaceActive else {
            return
        }

        let now = Date()
        applyLocalRateLimitResetsIfNeeded(relativeTo: now)

        guard !shouldPausePeriodicRefreshTimersForPowerSaving else {
            return
        }

        let identities = rateLimitCandidateIdentityKeys()
        guard !identities.isEmpty else {
            return
        }

        for identityKey in identities {
            guard shouldRefreshRateLimits(for: identityKey, relativeTo: now) else {
                continue
            }

            await refreshRateLimitsNow(for: identityKey)
        }
    }

    private func refreshRateLimitsNow(for identityKey: String) async {
        guard !rateLimitRefreshesInFlight.contains(identityKey) else {
            return
        }

        rateLimitRefreshesInFlight.insert(identityKey)
        defer {
            rateLimitRefreshesInFlight.remove(identityKey)
        }

        guard let account = try? fetchAccounts().first(where: { $0.identityKey == identityKey }) else {
            pendingForcedRateLimitRefreshes.remove(identityKey)
            return
        }

        let linkedLocation = identityKey == activeIdentityKey
            ? ((try? await authFileManager.linkedLocation()) ?? nil)
            : nil
        let request = CodexRateLimitRequest(
            identityKey: identityKey,
            credentials: await bestAvailableRateLimitCredentials(for: account),
            linkedLocation: linkedLocation,
            isCurrentAccount: identityKey == activeIdentityKey
        )

        let result = await rateLimitProvider.fetchSnapshot(for: request)
        pendingForcedRateLimitRefreshes.remove(identityKey)

        do {
            guard let account = try fetchAccounts().first(where: { $0.identityKey == identityKey }) else {
                return
            }

            if let snapshot = result.snapshot {
                let adjustedSnapshot = snapshot.applyingResetBoundaries()
                if shouldReplaceExistingRateLimitSnapshot(adjustedSnapshot, for: identityKey) {
                    rateLimitSnapshotsByIdentityKey[identityKey] = adjustedSnapshot

                    if RateLimitAccountUpdater.apply(adjustedSnapshot, to: account) {
                        try requireModelContext().save()
                        publishSharedState()
                    }
                }
            }

            switch result.remoteFailure {
            case nil:
                rateLimitFailureBackoffUntil.removeValue(forKey: identityKey)
                rateLimitFailureBackoffDurations.removeValue(forKey: identityKey)
                if account.isUnavailable {
                    _ = AccountAvailabilityUpdater.markAvailable(account)
                    try requireModelContext().save()
                    publishSharedState()
                }

            case .some(let failure):
                if failure.isAuthoritativeAuthInvalidation {
                    await handleAuthoritativeUnavailableAccount(account, reason: .unauthorized)
                    return
                }
                scheduleRateLimitFailureBackoff(for: identityKey, failure: failure)
            }
        } catch {
            logger.error("Rate-limit refresh failed for account \(identityKey, privacy: .private): \(String(describing: error), privacy: .private)")
        }
    }

    private func handleAuthoritativeUnavailableAccount(
        _ account: StoredAccount,
        reason: StoredAccountUnavailableReason
    ) async {
        if CodexSharedPreferences.automaticallyRemoveAccounts {
            await removeAccountBecauseUnavailable(account, reason: reason)
            return
        }

        do {
            if AccountAvailabilityUpdater.markUnavailable(account, reason: reason) {
                try requireModelContext().save()
                publishSharedState()
            }
        } catch {
            logger.error("Couldn't mark account unavailable: \(String(describing: error), privacy: .private)")
        }
    }

    private func removeAccountBecauseUnavailable(
        _ account: StoredAccount,
        reason: StoredAccountUnavailableReason
    ) async {
        logger.info("Auto-removing unavailable account \(account.identityKey, privacy: .private) reason \(reason.rawValue, privacy: .public)")
        _ = await removeAccountsNow(withIDs: [account.id], allowsInteractiveRecovery: false)
    }

    private func scheduleRateLimitFailureBackoff(
        for identityKey: String,
        failure: CodexRateLimitFetchFailure
    ) {
        switch failure {
        case .cancelled, .missingCredentials:
            return

        case .rateLimited(let retryAfter) where (retryAfter ?? 0) > 0:
            let requestedBackoff = retryAfter ?? Self.initialRateLimitFailureBackoff
            rateLimitFailureBackoffUntil[identityKey] = Date().addingTimeInterval(requestedBackoff)
            rateLimitFailureBackoffDurations[identityKey] = min(
                max(requestedBackoff, Self.initialRateLimitFailureBackoff) * 2,
                Self.maximumRateLimitFailureBackoff
            )

        default:
            let fallbackBackoff = rateLimitFailureBackoffDurations[identityKey] ?? Self.initialRateLimitFailureBackoff
            rateLimitFailureBackoffUntil[identityKey] = Date().addingTimeInterval(fallbackBackoff)
            rateLimitFailureBackoffDurations[identityKey] = min(
                max(fallbackBackoff, Self.initialRateLimitFailureBackoff) * 2,
                Self.maximumRateLimitFailureBackoff
            )
        }
    }

    private func applyLocalRateLimitResetsIfNeeded(relativeTo now: Date) {
        do {
            // If the server already told us an exact reset timestamp, we can
            // flip the UI back to 100% locally instead of waiting for the next
            // network round-trip.
            var didChange = false
            let accountsByIdentityKey = firstAccountByIdentityKey(from: try fetchAccounts())

            for identityKey in rateLimitCandidateIdentityKeys() {
                guard
                    let existingSnapshot = rateLimitSnapshotsByIdentityKey[identityKey],
                    let account = accountsByIdentityKey[identityKey]
                else {
                    continue
                }

                let adjustedSnapshot = existingSnapshot.applyingResetBoundaries(relativeTo: now)
                guard adjustedSnapshot != existingSnapshot else {
                    continue
                }

                rateLimitSnapshotsByIdentityKey[identityKey] = adjustedSnapshot
                didChange = RateLimitAccountUpdater.apply(adjustedSnapshot, to: account) || didChange
            }

            if didChange {
                try requireModelContext().save()
                publishSharedState()
            }
        } catch {
            logger.error("Local rate-limit reset handling failed: \(String(describing: error), privacy: .private)")
        }
    }

    private func shouldRefreshRateLimits(for identityKey: String, relativeTo now: Date) -> Bool {
        if pendingForcedRateLimitRefreshes.contains(identityKey) {
            return true
        }

        if let backoffUntil = rateLimitFailureBackoffUntil[identityKey], backoffUntil > now {
            return false
        }

        let refreshInterval = identityKey == activeIdentityKey
            ? Self.currentAccountRateLimitRefreshInterval
            : Self.visibleAccountRateLimitRefreshInterval

        if let snapshot = rateLimitSnapshotsByIdentityKey[identityKey] {
            if let nextResetAt = snapshot.nextResetAt, now >= nextResetAt {
                return true
            }

            return now.timeIntervalSince(snapshot.fetchedAt) >= refreshInterval
        }

        do {
            if let account = try fetchAccounts().first(where: { $0.identityKey == identityKey }) {
                if let observedAt = account.rateLimitsObservedAt {
                    return now.timeIntervalSince(observedAt) >= refreshInterval
                }
            }
        } catch {
            return true
        }

        return true
    }

    private func shouldReplaceExistingRateLimitSnapshot(
        _ snapshot: CodexRateLimitSnapshot,
        for identityKey: String
    ) -> Bool {
        guard let existingSnapshot = rateLimitSnapshotsByIdentityKey[identityKey] else {
            return true
        }

        if snapshot.observedAt > existingSnapshot.observedAt {
            return true
        }

        if snapshot.observedAt < existingSnapshot.observedAt {
            return false
        }

        if snapshot.source.priority != existingSnapshot.source.priority {
            return snapshot.source.priority > existingSnapshot.source.priority
        }

        return snapshot.fetchedAt >= existingSnapshot.fetchedAt
    }

    private func rateLimitCandidateIdentityKeys() -> [String] {
        var identities: [String] = []
        var seen = Set<String>()

        if let activeIdentityKey, !activeIdentityKey.isEmpty {
            identities.append(activeIdentityKey)
            seen.insert(activeIdentityKey)
        }

        for identityKey in visibleRateLimitIdentityCounts.keys.sorted() where !identityKey.isEmpty && !seen.contains(identityKey) {
            identities.append(identityKey)
            seen.insert(identityKey)
        }

        for identityKey in pendingForcedRateLimitRefreshes.sorted() where !identityKey.isEmpty && !seen.contains(identityKey) {
            identities.append(identityKey)
        }

        return identities
    }

    private nonisolated static func defaultLowPowerModeProvider() -> Bool {
        if #available(macOS 12.0, *) {
            return ProcessInfo.processInfo.isLowPowerModeEnabled
        }

        return false
    }

    // Read the internal battery percentage directly from macOS power-source
    // services. Desktops and machines that do not expose a battery return nil,
    // which means "do not pause solely because of battery level".
    private nonisolated static func defaultBatteryChargePercentProvider() -> Int? {
        let powerSourcesInfo = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let powerSources = IOPSCopyPowerSourcesList(powerSourcesInfo).takeRetainedValue() as Array

        for powerSource in powerSources {
            guard
                let description = IOPSGetPowerSourceDescription(powerSourcesInfo, powerSource)?
                    .takeUnretainedValue() as? [String: Any],
                let sourceType = description[kIOPSTypeKey as String] as? String,
                sourceType == kIOPSInternalBatteryType,
                (description[kIOPSIsPresentKey as String] as? Bool) != false,
                let currentCapacity = description[kIOPSCurrentCapacityKey as String] as? Int,
                let maximumCapacity = description[kIOPSMaxCapacityKey as String] as? Int,
                maximumCapacity > 0
            else {
                continue
            }

            let percentage = (Double(currentCapacity) / Double(maximumCapacity)) * 100
            return Int(percentage.rounded())
        }

        return nil
    }

    // CloudKit-backed SwiftData cannot enforce unique constraints, so the app
    // merges duplicates by identityKey when it boots with synced records.
    private func reconcileDuplicateAccountsIfNeeded() async -> Bool {
        do {
            let duplicateGroups = Dictionary(
                grouping: try fetchAccounts().filter { !$0.identityKey.isEmpty },
                by: \.identityKey
            ).values.filter { $0.count > 1 }

            guard !duplicateGroups.isEmpty else {
                return false
            }

            let modelContext = try requireModelContext()
            var didChange = false

            for group in duplicateGroups {
                let sortedGroup = group.sorted { lhs, rhs in
                    if lhs.createdAt != rhs.createdAt {
                        return lhs.createdAt < rhs.createdAt
                    }

                    return lhs.id.uuidString < rhs.id.uuidString
                }

                guard let survivor = sortedGroup.first else {
                    continue
                }

                for duplicate in sortedGroup.dropFirst() {
                    didChange = await mergeDuplicateAccount(duplicate, into: survivor) || didChange

                    if selection.contains(duplicate.id) {
                        selection.remove(duplicate.id)
                        selection.insert(survivor.id)
                    }

                    if renameTargetID == duplicate.id {
                        renameTargetID = survivor.id
                    }

                    modelContext.delete(duplicate)
                    didChange = true
                }
            }

            return didChange
        } catch {
            logger.error("Duplicate account reconciliation failed: \(String(describing: error), privacy: .private)")
            return false
        }
    }

    private func mergeDuplicateAccount(_ duplicate: StoredAccount, into survivor: StoredAccount) async -> Bool {
        var didChange = false

        if survivor.createdAt > duplicate.createdAt {
            survivor.createdAt = duplicate.createdAt
            didChange = true
        }

        if survivor.customOrder > duplicate.customOrder {
            survivor.customOrder = duplicate.customOrder
            didChange = true
        }

        if (duplicate.lastLoginAt ?? .distantPast) > (survivor.lastLoginAt ?? .distantPast) {
            survivor.lastLoginAt = duplicate.lastLoginAt
            didChange = true
        }

        if !survivor.isPinned && duplicate.isPinned {
            survivor.isPinned = true
            didChange = true
        }

        if (duplicate.rateLimitsObservedAt ?? .distantPast) > (survivor.rateLimitsObservedAt ?? .distantPast) {
            survivor.rateLimitsObservedAt = duplicate.rateLimitsObservedAt
            survivor.sevenDayLimitUsedPercent = duplicate.sevenDayLimitUsedPercent
            survivor.fiveHourLimitUsedPercent = duplicate.fiveHourLimitUsedPercent
            survivor.sevenDayResetsAt = duplicate.sevenDayResetsAt
            survivor.fiveHourResetsAt = duplicate.fiveHourResetsAt
            survivor.sevenDayDataStatusRaw = duplicate.sevenDayDataStatusRaw
            survivor.fiveHourDataStatusRaw = duplicate.fiveHourDataStatusRaw
            survivor.rateLimitDisplayVersion = duplicate.rateLimitDisplayVersion
            didChange = true
        }

        if survivor.rateLimitDisplayVersion == nil, duplicate.rateLimitDisplayVersion != nil {
            survivor.rateLimitDisplayVersion = duplicate.rateLimitDisplayVersion
            didChange = true
        }

        if
            (survivor.name.isEmpty || (Self.isGeneratedAccountName(survivor.name) && !Self.isGeneratedAccountName(duplicate.name))),
            !duplicate.name.isEmpty
        {
            survivor.name = duplicate.name
            didChange = true
        }

        if survivor.emailHint == nil, let duplicateEmail = duplicate.emailHint {
            survivor.emailHint = duplicateEmail
            didChange = true
        }

        if survivor.accountIdentifier == nil, let duplicateAccountIdentifier = duplicate.accountIdentifier {
            survivor.accountIdentifier = duplicateAccountIdentifier
            didChange = true
        }

        if survivor.iconSystemName == AccountIconOption.defaultOption.systemName,
           duplicate.iconSystemName != AccountIconOption.defaultOption.systemName {
            survivor.iconSystemName = duplicate.iconSystemName
            didChange = true
        }

        return didChange
    }

    private func uniqueAccountsPreservingDisplayOrder(_ accounts: [StoredAccount]) -> [StoredAccount] {
        var seenIDs = Set<UUID>()
        return accounts.filter { account in
            seenIDs.insert(account.id).inserted
        }
    }

    private static func draggedAccountIDs(from payloads: [String]) -> [UUID] {
        var seenIDs = Set<UUID>()
        return payloads
            .flatMap { payload in
                payload
                    .split(whereSeparator: \.isNewline)
                    .compactMap { UUID(uuidString: String($0)) }
            }
            .filter { accountID in
                seenIDs.insert(accountID).inserted
            }
    }

    private func moveAccounts(withIDs movingIDs: [UUID], to destinationIndex: Int, visibleAccounts: [StoredAccount]) {
        let orderedMovingIDs = visibleAccounts.compactMap { account in
            movingIDs.contains(account.id) ? account.id : nil
        }
        guard !orderedMovingIDs.isEmpty, !visibleAccounts.isEmpty else {
            return
        }

        let movingIDSet = Set(orderedMovingIDs)
        let boundedDestinationIndex = min(max(destinationIndex, 0), visibleAccounts.count)
        let movingRowsBeforeDestination = visibleAccounts[..<boundedDestinationIndex].reduce(into: 0) { count, account in
            if movingIDSet.contains(account.id) {
                count += 1
            }
        }
        let insertionIndex = max(0, boundedDestinationIndex - movingRowsBeforeDestination)

        let movingAccounts = visibleAccounts.filter { movingIDSet.contains($0.id) }
        var reorderedAccounts = visibleAccounts.filter { !movingIDSet.contains($0.id) }
        let boundedInsertionIndex = min(insertionIndex, reorderedAccounts.count)
        reorderedAccounts.insert(contentsOf: movingAccounts, at: boundedInsertionIndex)

        guard reorderedAccounts.map(\.id) != visibleAccounts.map(\.id) else {
            return
        }

        persistCustomOrder(for: reorderedAccounts)
    }

    private func persistCustomOrder(for reorderedAccounts: [StoredAccount]) {
        let persistedAccounts = AccountsPresentationLogic.customOrderPersistenceSequence(
            for: reorderedAccounts
        )

        for (index, account) in persistedAccounts.enumerated() {
            account.customOrder = Double(index)
            _ = account.normalizeLegacyLocalOnlyFields()
        }

        do {
            try requireModelContext().save()
            publishSharedState()
        } catch {
            present(error, title: "Couldn't Reorder Accounts")
        }
    }

    private func sortedAccounts(from accounts: [StoredAccount]) -> [StoredAccount] {
        AccountsPresentationLogic.sortedAccounts(
            from: accounts,
            sortCriterion: sortCriterion,
            sortDirection: sortDirection
        )
    }

    private func publishSharedState(immediate: Bool = false) {
        guard !Self.isRunningMainApplicationUnitTests else {
            return
        }

        sharedStatePublishTask?.cancel()
        sharedStatePublishTask = Task.detached(priority: .utility) { [weak self] in
            let sharedStateLogger = Logger(
                subsystem: Bundle.main.bundleIdentifier ?? "CodexSwitcher",
                category: "SharedState"
            )

            do {
                if !immediate {
                    try? await Task.sleep(for: .milliseconds(150))
                    try Task.checkCancellation()
                }
                let sharedState = try await MainActor.run { [weak self] in
                    guard let self else {
                        throw CancellationError()
                    }

                    return try self.makeSharedState()
                }
                try Task.checkCancellation()
                try CodexSharedStateStore().saveMergingRuntimeFields(sharedState)
                try Task.checkCancellation()
                await RateLimitResetNotificationScheduler.shared.synchronize(with: sharedState)
                try Task.checkCancellation()
                do {
                    try await CodexSpotlightIndexer.refresh(with: sharedState)
                } catch {
                    sharedStateLogger.error(
                        "Couldn't refresh Spotlight index from shared state: \(String(describing: error), privacy: .private)"
                    )
                }
                await MainActor.run {
                    CodexSwitcherAppShortcuts.updateAppShortcutParameters()
                }
                CodexSharedSurfaceReloader.reloadAll()
            } catch is CancellationError {
                return
            } catch {
                sharedStateLogger.error("Couldn't publish shared widget state: \(String(describing: error), privacy: .private)")
            }
        }
    }

    private func makeSharedState() throws -> SharedCodexState {
        let allAccounts = try fetchAccounts()
        let sharedAccounts = sortedAccounts(from: allAccounts)
            .filter { !$0.identityKey.isEmpty }
            .map { account in
                SharedCodexAccountRecord(
                    id: account.identityKey,
                    name: account.name,
                    iconSystemName: account.iconSystemName,
                    emailHint: account.emailHint,
                    accountIdentifier: account.accountIdentifier,
                    authModeRaw: account.authModeRaw,
                    lastLoginAt: account.lastLoginAt,
                    sevenDayLimitUsedPercent: account.sevenDayLimitUsedPercent,
                    fiveHourLimitUsedPercent: account.fiveHourLimitUsedPercent,
                    sevenDayResetsAt: account.sevenDayResetsAt,
                    fiveHourResetsAt: account.fiveHourResetsAt,
                    sevenDayDataStatusRaw: account.sevenDayDataStatus.rawValue,
                    fiveHourDataStatusRaw: account.fiveHourDataStatus.rawValue,
                    rateLimitsObservedAt: account.rateLimitsObservedAt,
                    sortOrder: account.customOrder,
                    isPinned: account.isPinned,
                    hasLocalSnapshot: hasLocalSnapshot(for: account),
                    availabilityRaw: account.availability.rawValue
                )
            }

        return SharedCodexState(
            schemaVersion: SharedCodexState.currentSchemaVersion,
            authState: SharedCodexAuthState(authAccessState: authAccessState),
            linkedFolderPath: linkedFolderPath,
            currentAccountID: activeIdentityKey,
            selectedAccountID: selectedSharedAccountIdentityKey(from: allAccounts),
            selectedAccountIsLive: isPrimarySelectionContextPresented,
            accounts: sharedAccounts,
            updatedAt: .now
        )
    }

    private func selectedSharedAccountIdentityKey(from accounts: [StoredAccount]) -> String? {
        guard isPrimarySelectionContextPresented else {
            return nil
        }

        guard selection.count == 1, let selectedID = selection.first else {
            return nil
        }

        return accounts.first(where: { $0.id == selectedID })?.identityKey
    }

    func sharedStateForTesting() throws -> SharedCodexState {
        try makeSharedState()
    }

    private nonisolated static var isRunningMainApplicationUnitTests: Bool {
        Bundle.main.bundleIdentifier == CodexSharedApplicationIdentity.mainApplicationBundleIdentifier
            && ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private func fetchAccounts() throws -> [StoredAccount] {
        let modelContext = try requireModelContext()
        let descriptor = FetchDescriptor<StoredAccount>()
        return try modelContext.fetch(descriptor)
    }

    private func consumePendingAccountOpenRequestIfNeeded() async {
        await waitForInitializationIfNeeded()

        do {
            guard let request = try CodexPendingAccountOpenRequestStore().consume() else {
                return
            }

            _ = await revealAccount(withIdentityKey: request.identityKey)
        } catch {
            logger.error(
                "Couldn't consume pending account-open request: \(String(describing: error), privacy: .private)"
            )
        }
    }

    @discardableResult
    private func revealAccount(withIdentityKey identityKey: String) async -> Bool {
        await waitForInitializationIfNeeded()

        let normalizedIdentityKey = identityKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedIdentityKey.isEmpty else {
            return false
        }

        do {
            guard let account = try fetchAccounts().first(where: { $0.identityKey == normalizedIdentityKey }) else {
                logger.error(
                    "Ignoring pending account-open request because no saved account matched \(normalizedIdentityKey, privacy: .private)"
                )
                return false
            }

            // Spotlight results should reveal the account even if a stale search
            // filter would otherwise keep the selected row off-screen.
            searchText = ""
            selection = [account.id]
            requestImmediateRateLimitRefresh(for: account.identityKey)
            return true
        } catch {
            logger.error("Couldn't reveal requested account: \(String(describing: error), privacy: .private)")
            return false
        }
    }

    private func account(withID id: UUID) throws -> StoredAccount? {
        try fetchAccounts().first(where: { $0.id == id })
    }

    private func requireAccount(withID id: UUID) throws -> StoredAccount {
        guard let account = try account(withID: id) else {
            throw ControllerError.accountNotFound
        }

        return account
    }

    private func requireModelContext() throws -> ModelContext {
        guard let modelContainer else {
            throw ControllerError.missingModelContext
        }

        return modelContainer.mainContext
    }

    private func present(_ error: Error, title: String) {
        guard !Self.shouldSilentlyDismiss(error) else {
            return
        }

        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        present(UserFacingAlert(title: title, message: message))
    }

    private func present(_ alert: UserFacingAlert) {
        presentedAlert = alert
    }

    private static func shouldPresentUnexpectedAuthAlert(for error: AuthFileAccessError) -> Bool {
        switch error {
        case .accessRequired, .missingAuthFile, .locationUnavailable, .accessDenied, .unsupportedCredentialStore:
            false
        case .invalidSelection, .cancelled, .unreadable, .unwritable, .verificationFailed:
            true
        }
    }

    // Cancelling the folder picker is an intentional user choice, not an error
    // that should interrupt the UI with an alert.
    private static func shouldSilentlyDismiss(_ error: Error) -> Bool {
        if let accessError = error as? AuthFileAccessError, accessError.isUserCancellation {
            return true
        }

        if error is CancellationError {
            return true
        }

        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError
    }

    private static func isGeneratedAccountName(_ name: String) -> Bool {
        generatedAccountIndex(from: name) != nil
    }

    private static func generatedAccountIndex(from name: String) -> Int? {
        guard name.hasPrefix("Account ") else {
            return nil
        }

        return Int(name.dropFirst("Account ".count))
    }

    private func defaultName(for snapshot: CodexAuthSnapshot, existingAccounts: [StoredAccount]) -> String {
        if let preferredEmail = snapshot.email?.trimmingCharacters(in: .whitespacesAndNewlines), !preferredEmail.isEmpty {
            return preferredEmail
        }

        return nextGeneratedAccountName(existingAccounts: existingAccounts)
    }

    private func nextGeneratedAccountName(existingAccounts: [StoredAccount]) -> String {
        let usedIndices = Set(existingAccounts.compactMap { Self.generatedAccountIndex(from: $0.name) })

        var candidateIndex = 1
        while usedIndices.contains(candidateIndex) {
            candidateIndex += 1
        }

        return "Account \(candidateIndex)"
    }

    private func firstAccountByIdentityKey(from accounts: [StoredAccount]) -> [String: StoredAccount] {
        var accountsByIdentityKey: [String: StoredAccount] = [:]

        for account in accounts {
            let normalizedIdentityKey = account.identityKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedIdentityKey.isEmpty else {
                continue
            }

            if accountsByIdentityKey[normalizedIdentityKey] == nil {
                accountsByIdentityKey[normalizedIdentityKey] = account
            }
        }

        return accountsByIdentityKey
    }

}

private enum PendingLocationAction {
    case captureCurrentAccount
    case switchAccount(UUID)
    case refresh
}

private enum AutopilotTrigger {
    case started
    case appBecameActive
    case systemWoke
    case scheduled
    case sessionBecameQuiet
    case testing

    var forcesImmediateRateLimitRefresh: Bool {
        switch self {
        case .started, .appBecameActive, .systemWoke, .testing:
            true
        case .scheduled, .sessionBecameQuiet:
            false
        }
    }

    var shouldPreserveImmediatePriorityWhenDeferred: Bool {
        switch self {
        case .started, .appBecameActive, .systemWoke:
            true
        case .scheduled, .sessionBecameQuiet, .testing:
            false
        }
    }
}

private enum ControllerError: LocalizedError {
    case missingModelContext
    case accountNotFound
    case accountUnavailable
    case accountLimitReached
    case noSupportedAccountArchives
    case accountArchiveIdentityMismatch
    case accountNeedsLocalSnapshotForExport
    case pasteboardWriteFailed

    var errorDescription: String? {
        switch self {
        case .missingModelContext:
            "The app isn't ready to edit accounts yet."
        case .accountNotFound:
            "That account no longer exists."
        case .accountUnavailable:
            "That saved account is no longer available. Keep it and capture a fresh login, or remove it from Codex Switcher."
        case .accountLimitReached:
            "Codex Switcher supports up to 1000 saved accounts."
        case .noSupportedAccountArchives:
            "No supported .cxa files were provided."
        case .accountArchiveIdentityMismatch:
            "That .cxa file doesn't match the account snapshot it contains."
        case .accountNeedsLocalSnapshotForExport:
            "That saved account needs a local capture on this Mac before it can be exported."
        case .pasteboardWriteFailed:
            "Codex Switcher couldn't put the account archive on the clipboard."
        }
    }
}

private extension SharedCodexAuthState {
    init(authAccessState: AuthAccessState) {
        switch authAccessState {
        case .unlinked:
            self = .unlinked
        case .ready:
            self = .ready
        case .missingAuthFile:
            self = .loggedOut
        case .locationUnavailable:
            self = .locationUnavailable
        case .accessDenied:
            self = .accessDenied
        case .corruptAuthFile:
            self = .corruptAuthFile
        case .unsupportedCredentialStore:
            self = .unsupportedCredentialStore
        }
    }
}
