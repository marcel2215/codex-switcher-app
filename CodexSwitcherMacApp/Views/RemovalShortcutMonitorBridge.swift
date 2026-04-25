//
//  RemovalShortcutMonitorBridge.swift
//  Codex Switcher Mac App
//
//  Created by Marcel Kwiatkowski on 2026-04-25.
//

import AppKit
import SwiftUI

/// Handles Delete/Backspace key equivalents before the menu system consumes
/// modified combinations such as Command-Delete.
struct RemovalShortcutMonitorBridge: NSViewRepresentable {
    let isEnabled: Bool
    let onRemove: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true
        context.coordinator.install(for: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onRemove = onRemove
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    static func isRemovalKeyCode(_ keyCode: UInt16) -> Bool {
        keyCode == KeyCode.delete || keyCode == KeyCode.forwardDelete
    }

    final class Coordinator {
        var isEnabled = false
        var onRemove: (() -> Void)?

        private weak var view: NSView?
        private var localMonitor: Any?

        func install(for view: NSView) {
            self.view = view

            guard localMonitor == nil else {
                return
            }

            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
                guard let self, self.shouldHandle(event) else {
                    return event
                }

                self.onRemove?()
                return nil
            }
        }

        func uninstall() {
            if let localMonitor {
                NSEvent.removeMonitor(localMonitor)
                self.localMonitor = nil
            }
        }

        private func shouldHandle(_ event: NSEvent) -> Bool {
            guard
                isEnabled,
                Self.isDeletionShortcut(event),
                let window = view?.window,
                NSApp.keyWindow === window,
                event.window == nil || event.window === window,
                !Self.isTextEditing(in: window)
            else {
                return false
            }

            return true
        }

        private static func isDeletionShortcut(_ event: NSEvent) -> Bool {
            event.type == .keyDown
                && RemovalShortcutMonitorBridge.isRemovalKeyCode(event.keyCode)
        }

        private static func isTextEditing(in window: NSWindow) -> Bool {
            guard let responder = window.firstResponder else {
                return false
            }

            if responder is NSTextView || responder is NSTextField {
                return true
            }

            guard let responderView = responder as? NSView else {
                return false
            }

            return responderView.hasAncestor { view in
                view is NSTextView || view is NSTextField
            }
        }
    }

    private enum KeyCode {
        static let delete: UInt16 = 51
        static let forwardDelete: UInt16 = 117
    }
}

private extension NSView {
    func hasAncestor(where matches: (NSView) -> Bool) -> Bool {
        var current: NSView? = self

        while let view = current {
            if matches(view) {
                return true
            }

            current = view.superview
        }

        return false
    }
}
