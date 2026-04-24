//
//  SettingsWindowController.swift
//  Docky
//

import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?

    convenience init() {
        let tabViewController = SettingsTabViewController()
        let window = NSWindow(contentViewController: tabViewController)
        window.setContentSize(NSSize(width: 560, height: 420))
        window.styleMask.insert(.closable)
        window.styleMask.insert(.miniaturizable)
        window.styleMask.insert(.resizable)
        window.title = "Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = false
        window.center()
        window.isReleasedWhenClosed = false
        self.init(window: window)
        window.delegate = self
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}

private final class SettingsTabViewController: NSTabViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        tabStyle = .toolbar
        canPropagateSelectedChildViewControllerTitle = false
        transitionOptions = []

        addTabViewItem(makeTab(
            label: "Appearance",
            imageName: "paintbrush",
            view: AppearanceSettingsView()
        ))
        addTabViewItem(makeTab(
            label: "Behavior",
            imageName: "switch.2",
            view: BehaviorSettingsView()
        ))
        addTabViewItem(makeTab(
            label: "App Icons",
            imageName: "app.badge",
            view: AppIconsSettingsView()
        ))
        addTabViewItem(makeTab(
            label: "Permissions",
            imageName: "lock.shield",
            view: PermissionsSettingsView()
        ))
        addTabViewItem(makeTab(
            label: "Actions",
            imageName: "list.bullet.rectangle",
            view: ActionCatalogSettingsView()
        ))
    }

    private func makeTab(label: String, imageName: String, view: some View) -> NSTabViewItem {
        let item = NSTabViewItem(viewController: NSHostingController(rootView: view))
        item.label = label
        item.image = NSImage(systemSymbolName: imageName, accessibilityDescription: label)
        return item
    }
}
