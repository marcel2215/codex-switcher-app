//
//  ListDoubleClickBridge.swift
//  Codex Switcher
//
//  Created by Codex on 2026-04-07.
//

import AppKit
import SwiftUI

/// Hooks into the backing NSTableView so double-click stays native and
/// does not interfere with the list's normal single-click selection.
struct ListDoubleClickBridge<RowID: Hashable>: NSViewRepresentable {
    let rowIDs: [RowID]
    let onDoubleClick: (RowID) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.rowIDs = rowIDs
        context.coordinator.onDoubleClick = onDoubleClick

        DispatchQueue.main.async {
            guard let tableView = Self.findTableView(near: nsView) else {
                return
            }

            context.coordinator.install(on: tableView)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    private static func findTableView(near view: NSView) -> NSTableView? {
        var ancestor: NSView? = view

        while let current = ancestor {
            if let tableView = findTableView(in: current) {
                return tableView
            }

            ancestor = current.superview
        }

        return nil
    }

    private static func findTableView(in root: NSView) -> NSTableView? {
        if let tableView = root as? NSTableView {
            return tableView
        }

        for subview in root.subviews {
            if let tableView = findTableView(in: subview) {
                return tableView
            }
        }

        return nil
    }

    final class Coordinator: NSObject {
        var rowIDs: [RowID] = []
        var onDoubleClick: ((RowID) -> Void)?

        private weak var tableView: NSTableView?
        private weak var previousTarget: AnyObject?
        private var previousDoubleAction: Selector?

        func install(on tableView: NSTableView) {
            if self.tableView === tableView,
               tableView.target === self,
               tableView.doubleAction == #selector(handleDoubleClick(_:)) {
                return
            }

            uninstall()

            self.tableView = tableView
            previousTarget = tableView.target as AnyObject?
            previousDoubleAction = tableView.doubleAction
            tableView.target = self
            tableView.doubleAction = #selector(handleDoubleClick(_:))
        }

        func uninstall() {
            guard let tableView else {
                previousTarget = nil
                previousDoubleAction = nil
                return
            }

            if tableView.target === self {
                tableView.target = previousTarget
                tableView.doubleAction = previousDoubleAction
            }

            self.tableView = nil
            previousTarget = nil
            previousDoubleAction = nil
        }

        @objc
        private func handleDoubleClick(_ sender: Any?) {
            guard
                let tableView,
                rowIDs.indices.contains(tableView.clickedRow)
            else {
                return
            }

            onDoubleClick?(rowIDs[tableView.clickedRow])
        }
    }
}
