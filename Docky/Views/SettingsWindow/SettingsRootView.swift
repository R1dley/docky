//
//  SettingsRootView.swift
//  Docky
//

import SwiftUI

private enum SettingsPane: String, CaseIterable, Identifiable {
    case product
    case appearance
    case behavior
    case launchpad
    case windowManagement
    case appIcons
    case permissions
    case actions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .product:
            "Product"
        case .appearance:
            "Appearance"
        case .behavior:
            "Behavior"
        case .launchpad:
            "Launchpad"
        case .windowManagement:
            "Window Management"
        case .appIcons:
            "App Icons"
        case .permissions:
            "Permissions"
        case .actions:
            "Actions"
        }
    }

    var symbolName: String {
        switch self {
        case .product:
            "shippingbox"
        case .appearance:
            "paintbrush"
        case .behavior:
            "switch.2"
        case .launchpad:
            "square.grid.3x3.fill"
        case .windowManagement:
            "rectangle.on.rectangle"
        case .appIcons:
            "app.badge"
        case .permissions:
            "lock.shield"
        case .actions:
            "list.bullet.rectangle"
        }
    }

    var subtitle: String {
        switch self {
        case .product:
            "Register Docky Pro and review which features are gated."
        case .appearance:
            "Customize Docky’s look, chrome, and window tint."
        case .behavior:
            "Control placement, autohide, and system Dock behavior."
        case .launchpad:
            "Configure the Launchpad overlay grid and optional global shortcut."
        case .windowManagement:
            "Configure global window switching and shortcut behavior."
        case .appIcons:
            "Choose per-app icon overrides for pinned and running apps."
        case .permissions:
            "Review access status and request optional macOS permissions."
        case .actions:
            "Inspect loaded action packages and catalog diagnostics."
        }
    }
    
    var isPro: Bool {
        switch self {
        case .launchpad, .windowManagement, .appIcons, .actions:
            true
        case .product, .appearance, .behavior, .permissions:
            false
        }
    }

    static var allCases: [SettingsPane] = [.product, .appearance, .behavior, .launchpad, .windowManagement, .appIcons, .permissions, .actions]
}

struct SettingsRootView: View {
    @State private var selection: SettingsPane = .product

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $selection) { pane in
                HStack(spacing: 10) {
                    Label(pane.title, systemImage: pane.symbolName)
                    Spacer(minLength: 8)
                    if pane.isPro {
                        ProBadge()
                    }
                }
                .tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .listStyle(.sidebar)
        } detail: {
            SettingsDetailView(pane: selection)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SettingsDetailView: View {
    let pane: SettingsPane

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            selectedView
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var selectedView: some View {
        switch pane {
        case .product:
            ProductSettingsView()
        case .appearance:
            AppearanceSettingsView()
        case .behavior:
            BehaviorSettingsView()
        case .launchpad:
            LaunchpadSettingsView()
        case .windowManagement:
            WindowManagementSettingsView()
        case .appIcons:
            AppIconsSettingsView()
        case .permissions:
            PermissionsSettingsView()
        case .actions:
            ActionCatalogSettingsView()
        }
    }
}
