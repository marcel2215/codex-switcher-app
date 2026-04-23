//
//  AppSingleInstanceCoordinator.swift
//  Codex Switcher Mac App
//
//  Created by Marcel Kwiatkowski on 2026-04-10.
//

import AppKit
import Foundation

@MainActor
struct AppSingleInstanceCoordinator {
    typealias RunningApplicationsProvider = (String) -> [CodexSharedAppProcessIdentity]
    typealias CommandEnqueuer = (CodexSharedAppCommand) throws -> Void
    typealias SignalPoster = () -> Void

    private let bundleIdentifier: String
    private let currentProcess: CodexSharedAppProcessIdentity
    private let runningApplicationsProvider: RunningApplicationsProvider
    private let commandEnqueuer: CommandEnqueuer
    private let signalPoster: SignalPoster

    init(
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "CodexSwitcher",
        currentProcess: CodexSharedAppProcessIdentity = .current,
        runningApplicationsProvider: @escaping RunningApplicationsProvider = { bundleIdentifier in
            NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleIdentifier)
                .map(CodexSharedAppProcessIdentity.init(runningApplication:))
        },
        commandEnqueuer: @escaping CommandEnqueuer = { command in
            try CodexSharedAppCommandQueue().enqueue(command)
        },
        signalPoster: @escaping SignalPoster = {
            CodexSharedAppCommandSignal.postCommandQueuedSignal()
        }
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.currentProcess = currentProcess
        self.runningApplicationsProvider = runningApplicationsProvider
        self.commandEnqueuer = commandEnqueuer
        self.signalPoster = signalPoster
    }

    /// Keep the newest launch alive by asking every older instance of the same
    /// bundle to terminate itself through the shared command queue.
    @discardableResult
    func requestTerminationOfOlderInstances() throws -> [CodexSharedAppProcessIdentity] {
        let olderInstances = runningApplicationsProvider(bundleIdentifier)
            .filter { $0.processIdentifier != currentProcess.processIdentifier }
            .filter { $0.wasLaunchedBefore(currentProcess) }
            .sorted { $0.wasLaunchedBefore($1) }

        guard !olderInstances.isEmpty else {
            return []
        }

        for olderInstance in olderInstances {
            try commandEnqueuer(
                CodexSharedAppCommand(
                    action: .quitApplication,
                    targetProcess: olderInstance
                )
            )
        }

        signalPoster()
        return olderInstances
    }
}
