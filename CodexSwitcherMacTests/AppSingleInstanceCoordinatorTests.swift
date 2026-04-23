//
//  AppSingleInstanceCoordinatorTests.swift
//  Codex Switcher Mac Tests
//
//  Created by Marcel Kwiatkowski on 2026-04-10.
//

import Foundation
import Testing
@testable import Codex_Switcher_Mac_App

@MainActor
struct AppSingleInstanceCoordinatorTests {
    @Test func coordinatorRequestsOnlyOlderInstancesToQuit() throws {
        let launchBase = Date(timeIntervalSince1970: 1_000)
        let olderFirst = CodexSharedAppProcessIdentity(
            processIdentifier: 101,
            launchDate: launchBase
        )
        let olderSecond = CodexSharedAppProcessIdentity(
            processIdentifier: 102,
            launchDate: launchBase.addingTimeInterval(5)
        )
        let current = CodexSharedAppProcessIdentity(
            processIdentifier: 200,
            launchDate: launchBase.addingTimeInterval(10)
        )
        let newer = CodexSharedAppProcessIdentity(
            processIdentifier: 201,
            launchDate: launchBase.addingTimeInterval(15)
        )
        let recorder = CommandRecorder()

        let coordinator = AppSingleInstanceCoordinator(
            bundleIdentifier: "com.example.codex-switcher",
            currentProcess: current,
            runningApplicationsProvider: { _ in
                [newer, olderSecond, current, olderFirst]
            },
            commandEnqueuer: { recorder.commands.append($0) },
            signalPoster: { recorder.signalCount += 1 }
        )

        let terminatedInstances = try coordinator.requestTerminationOfOlderInstances()

        #expect(terminatedInstances == [olderFirst, olderSecond])
        #expect(recorder.commands.map(\.action) == [.quitApplication, .quitApplication])
        #expect(recorder.commands.map(\.targetProcess) == [olderFirst, olderSecond].map(Optional.some))
        #expect(recorder.signalCount == 1)
    }

    @Test func coordinatorDoesNothingWhenCurrentInstanceIsNewest() throws {
        let launchBase = Date(timeIntervalSince1970: 2_000)
        let current = CodexSharedAppProcessIdentity(
            processIdentifier: 200,
            launchDate: launchBase.addingTimeInterval(10)
        )
        let newer = CodexSharedAppProcessIdentity(
            processIdentifier: 300,
            launchDate: launchBase.addingTimeInterval(20)
        )
        let recorder = CommandRecorder()

        let coordinator = AppSingleInstanceCoordinator(
            bundleIdentifier: "com.example.codex-switcher",
            currentProcess: current,
            runningApplicationsProvider: { _ in [current, newer] },
            commandEnqueuer: { recorder.commands.append($0) },
            signalPoster: { recorder.signalCount += 1 }
        )

        let terminatedInstances = try coordinator.requestTerminationOfOlderInstances()

        #expect(terminatedInstances.isEmpty)
        #expect(recorder.commands.isEmpty)
        #expect(recorder.signalCount == 0)
    }

    @Test func quitCommandRoutingHonorsTargetProcess() {
        let current = CodexSharedAppProcessIdentity(
            processIdentifier: 200,
            launchDate: Date(timeIntervalSince1970: 3_000)
        )
        let target = CodexSharedAppProcessIdentity(
            processIdentifier: 100,
            launchDate: Date(timeIntervalSince1970: 2_000)
        )
        let targetedCommand = CodexSharedAppCommand(
            action: .quitApplication,
            targetProcess: target
        )

        #expect(
            targetedCommand.quitRoutingDecision(
                currentProcess: current,
                runningProcesses: [current, target]
            ) == .waitForTargetProcess
        )
        #expect(
            targetedCommand.quitRoutingDecision(
                currentProcess: target,
                runningProcesses: [current, target]
            ) == .terminateCurrentProcess
        )
        #expect(
            targetedCommand.quitRoutingDecision(
                currentProcess: current,
                runningProcesses: [current]
            ) == .discardStaleCommand
        )
        #expect(
            CodexSharedAppCommand(action: .quitApplication)
                .quitRoutingDecision(
                    currentProcess: current,
                    runningProcesses: [current]
                ) == .terminateCurrentProcess
        )
    }
}

private final class CommandRecorder {
    var commands: [CodexSharedAppCommand] = []
    var signalCount = 0
}
