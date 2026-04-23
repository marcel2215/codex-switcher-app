//
//  MouseButtonMonitorBridge.swift
//  Codex Switcher Mac App
//
//  Created by Marcel Kwiatkowski on 2026-04-17.
//

import AppKit
import SwiftUI

/// Observes local mouse-up events without taking ownership of the list's drag
/// gesture, so SwiftUI's native row reordering can keep working unchanged.
struct MouseButtonMonitorBridge: NSViewRepresentable {
    let onLeftMouseUp: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true
        context.coordinator.install()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onLeftMouseUp = onLeftMouseUp
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator {
        var onLeftMouseUp: (() -> Void)?

        private var localMonitor: Any?

        func install() {
            guard localMonitor == nil else {
                return
            }

            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
                DispatchQueue.main.async {
                    self?.onLeftMouseUp?()
                }

                return event
            }
        }

        func uninstall() {
            if let localMonitor {
                NSEvent.removeMonitor(localMonitor)
                self.localMonitor = nil
            }
        }
    }
}
