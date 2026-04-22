//
//  PermissionsWindowController.swift
//  Docky
//

import AppKit
import SwiftUI

final class PermissionsWindowController: NSWindowController {
    var onComplete: (() -> Void)?

    convenience init(steps: [Permission]) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 620),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Docky Setup"
        window.subtitle = "Permissions"
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unifiedCompact
        window.isReleasedWhenClosed = false
        self.init(window: window)

        let view = PermissionsView(steps: steps) { [weak self] in
            self?.close()
            self?.onComplete?()
        }
        window.contentViewController = NSHostingController(rootView: view)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        centerWindowOnActiveScreen()
    }

    private func centerWindowOnActiveScreen() {
        guard let window else { return }

        let screen = window.screen ?? NSApp.keyWindow?.screen ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero
        guard !visibleFrame.equalTo(.zero) else { return }

        let windowFrame = window.frame
        let origin = NSPoint(
            x: visibleFrame.midX - windowFrame.width / 2,
            y: visibleFrame.midY - windowFrame.height / 2
        )
        window.setFrameOrigin(origin)
    }
}
