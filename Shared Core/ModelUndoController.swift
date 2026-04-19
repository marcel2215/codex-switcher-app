//
//  ModelUndoController.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-19.
//

import Foundation
import Observation
import OSLog
import SwiftData

@MainActor
@Observable
final class ModelUndoController: NSObject {
    private(set) var canUndo = false
    private(set) var canRedo = false
    private(set) var undoMenuTitle = "Undo"
    private(set) var redoMenuTitle = "Redo"

    @ObservationIgnored private var modelContext: ModelContext?
    @ObservationIgnored private weak var undoManager: UndoManager?
    @ObservationIgnored private var pendingPersistenceTask: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "CodexSwitcher",
        category: "ModelUndoController"
    )

    func configure(modelContext: ModelContext, undoManager: UndoManager?) {
        self.modelContext = modelContext
        if !modelContext.autosaveEnabled {
            // SwiftData's mainContext normally autosaves, but keep it explicit
            // here because undo/redo can reintroduce model rows outside the
            // controller's direct mutation paths.
            modelContext.autosaveEnabled = true
        }

        if modelContext.undoManager.map(ObjectIdentifier.init) != undoManager.map(ObjectIdentifier.init) {
            modelContext.undoManager = undoManager
        }

        let currentUndoManagerID = self.undoManager.map(ObjectIdentifier.init)
        let newUndoManagerID = undoManager.map(ObjectIdentifier.init)
        guard currentUndoManagerID != newUndoManagerID else {
            refreshAvailability()
            return
        }

        NotificationCenter.default.removeObserver(self)
        pendingPersistenceTask?.cancel()
        pendingPersistenceTask = nil
        self.undoManager = undoManager

        if let undoManager {
            startObservingUndoManager(undoManager)
        }

        refreshAvailability()
    }

    func undo() {
        guard let undoManager, undoManager.canUndo else {
            return
        }

        undoManager.undo()
        modelContext?.processPendingChanges()
        schedulePersistenceAfterUndoOrRedo()
        refreshAvailability()
    }

    func redo() {
        guard let undoManager, undoManager.canRedo else {
            return
        }

        undoManager.redo()
        modelContext?.processPendingChanges()
        schedulePersistenceAfterUndoOrRedo()
        refreshAvailability()
    }

    private func startObservingUndoManager(_ undoManager: UndoManager) {
        let notificationCenter = NotificationCenter.default
        let notificationNames: [Notification.Name] = [
            .NSUndoManagerCheckpoint,
            .NSUndoManagerDidUndoChange,
            .NSUndoManagerDidRedoChange,
        ]

        for notificationName in notificationNames {
            notificationCenter.addObserver(
                self,
                selector: #selector(handleUndoStateChange(_:)),
                name: notificationName,
                object: undoManager
            )
        }
    }

    @objc
    private func handleUndoStateChange(_ notification: Notification) {
        if notification.name == .NSUndoManagerDidUndoChange || notification.name == .NSUndoManagerDidRedoChange {
            schedulePersistenceAfterUndoOrRedo()
        }
        refreshAvailability()
    }

    private func refreshAvailability() {
        canUndo = undoManager?.canUndo ?? false
        canRedo = undoManager?.canRedo ?? false
        undoMenuTitle = undoManager?.undoMenuItemTitle ?? "Undo"
        redoMenuTitle = undoManager?.redoMenuItemTitle ?? "Redo"
    }

    /// Undo/redo mutates the live SwiftData context, but the framework does not
    /// finish materializing restored models until the next main-actor turn.
    /// Persist after that handoff so deleting an account and immediately
    /// undoing it restores the row reliably instead of racing the save.
    private func schedulePersistenceAfterUndoOrRedo() {
        pendingPersistenceTask?.cancel()
        pendingPersistenceTask = Task { @MainActor [weak self] in
            await Task.yield()
            await Task.yield()
            guard let self, !Task.isCancelled else {
                return
            }

            self.modelContext?.processPendingChanges()
            self.persistContextChangesIfNeeded()
            self.refreshAvailability()
            self.pendingPersistenceTask = nil
        }
    }

    /// Undo/redo mutates the live SwiftData context, and the app can reload
    /// shared state from disk before SwiftData's autosave fires. Save the
    /// settled state explicitly once the framework has finished processing the
    /// change.
    private func persistContextChangesIfNeeded() {
        guard let modelContext, modelContext.hasChanges else {
            return
        }

        do {
            try modelContext.save()
        } catch {
            logger.error("Couldn't save SwiftData changes after undo/redo: \(String(describing: error), privacy: .private)")
        }
    }
}
