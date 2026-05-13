//
//  SettingsRootView.swift
//  Docky
//

import SwiftUI

private enum SettingsPane: String, CaseIterable, Identifiable {
    case docky
    case appearanceGeneral
    case appearanceIndicators
    case appearanceTileLayout
    case appearanceWindowShape
    case appearanceWindowBackground
    case appearanceThemes
    case appIcons
    case behaviorGeneral
    case behaviorPlacement
    case behaviorVisibility
    case behaviorAppTileClick
    case behaviorAppFolders
    case behaviorWidgets
    case hiddenApps
    case launchpad
    case windowManagement
    case actions
    case behaviorLaunch
    case behaviorSystemDock
    case permissions
    case updates

    var id: String { rawValue }

    var title: String {
        switch self {
        case .docky: "Docky"
        case .appearanceGeneral: "General"
        case .appearanceIndicators: "Indicators"
        case .appearanceTileLayout: "Tile Layout"
        case .appearanceWindowShape: "Window Shape"
        case .appearanceWindowBackground: "Window Background"
        case .appearanceThemes: "Themes"
        case .appIcons: "App Icons"
        case .behaviorGeneral: "General"
        case .behaviorPlacement: "Placement"
        case .behaviorVisibility: "Visibility"
        case .behaviorAppTileClick: "App Tile Click"
        case .behaviorAppFolders: "App Folders"
        case .behaviorWidgets: "Widgets"
        case .hiddenApps: "Hidden Apps"
        case .launchpad: "Launchpad"
        case .windowManagement: "Window Management"
        case .actions: "Actions"
        case .behaviorLaunch: "Launch"
        case .behaviorSystemDock: "System Dock"
        case .permissions: "Permissions"
        case .updates: "Updates"
        }
    }

    var symbolName: String {
        switch self {
        case .docky: "shippingbox"
        case .appearanceGeneral: "slider.horizontal.3"
        case .appearanceIndicators: "circle.bottomhalf.filled"
        case .appearanceTileLayout: "square.grid.3x3"
        case .appearanceWindowShape: "rectangle.dashed"
        case .appearanceWindowBackground: "rectangle.fill"
        case .appearanceThemes: "paintpalette"
        case .appIcons: "app.badge"
        case .behaviorGeneral: "slider.horizontal.3"
        case .behaviorPlacement: "arrow.up.and.down.and.arrow.left.and.right"
        case .behaviorVisibility: "eye"
        case .behaviorAppTileClick: "cursorarrow.click"
        case .behaviorAppFolders: "folder"
        case .behaviorWidgets: "puzzlepiece.extension"
        case .hiddenApps: "eye.slash"
        case .launchpad: "square.grid.3x3.fill"
        case .windowManagement: "rectangle.on.rectangle"
        case .actions: "list.bullet.rectangle"
        case .behaviorLaunch: "power"
        case .behaviorSystemDock: "dock.rectangle"
        case .permissions: "lock.shield"
        case .updates: "arrow.trianglehead.clockwise"
        }
    }

    var tileColor: Color {
        switch self {
        case .docky: .purple
        case .appearanceGeneral: .teal
        case .appearanceIndicators: .green
        case .appearanceTileLayout: .orange
        case .appearanceWindowShape: .indigo
        case .appearanceWindowBackground: .blue
        case .appearanceThemes: .pink
        case .appIcons: .pink
        case .behaviorGeneral: .gray
        case .behaviorPlacement: .teal
        case .behaviorVisibility: .cyan
        case .behaviorAppTileClick: .mint
        case .behaviorAppFolders: .yellow
        case .behaviorWidgets: .purple
        case .hiddenApps: .gray
        case .launchpad: .indigo
        case .windowManagement: .blue
        case .actions: .red
        case .behaviorLaunch: .green
        case .behaviorSystemDock: .gray
        case .permissions: .red
        case .updates: .blue
        }
    }

    var isPro: Bool {
        switch self {
        case .launchpad, .windowManagement, .appIcons, .actions:
            true
        default:
            false
        }
    }
}

private struct SettingsSection: Identifiable {
    let id: String
    let title: String?
    let panes: [SettingsPane]
}

private let settingsSections: [SettingsSection] = [
    SettingsSection(id: "product", title: "Product", panes: [.docky]),
    SettingsSection(id: "appearance", title: "Appearance", panes: [
        .appearanceThemes,
        .appearanceGeneral,
        .appearanceIndicators,
        .appearanceTileLayout,
        .appearanceWindowShape,
        .appearanceWindowBackground,
        .appIcons
    ]),
    SettingsSection(id: "behavior", title: "Behavior", panes: [
        .behaviorGeneral,
        .behaviorPlacement,
        .behaviorVisibility,
        .behaviorAppTileClick,
        .behaviorAppFolders,
        .behaviorWidgets,
        .hiddenApps
    ]),
    SettingsSection(id: "features", title: "Features", panes: [
        .launchpad,
        .windowManagement,
        .actions
    ]),
    SettingsSection(id: "system", title: "System", panes: [
        .behaviorLaunch,
        .behaviorSystemDock,
        .permissions,
        .updates
    ])
]

struct SettingsRootView: View {
    @State private var selection: SettingsPane = .docky

    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif

        NavigationSplitView {
            List(selection: $selection) {
                ForEach(settingsSections) { section in
                    if let title = section.title {
                        Section(title) {
                            paneRows(section.panes)
                        }
                    } else {
                        Section {
                            paneRows(section.panes)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
            .listStyle(.sidebar)
        } detail: {
            SettingsDetailView(pane: selection)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func paneRows(_ panes: [SettingsPane]) -> some View {
        ForEach(panes) { pane in
            HStack(spacing: 8) {
                PaneIconBadge(symbol: pane.symbolName, color: pane.tileColor)
                Text(pane.title)
                Spacer(minLength: 8)
                if pane.isPro {
                    ProBadge()
                }
            }
            .tag(pane)
        }
    }
}

private struct PaneIconBadge: View {
    let symbol: String
    let color: Color

    @Environment(\.colorScheme) private var colorScheme

    private static let tileSize: CGFloat = 22
    private static let symbolSize: CGFloat = 12
    private static let cornerRadius: CGFloat = 5

    var body: some View {
        let isDark = colorScheme == .dark
        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
            .fill(isDark ? Color.black : color)
            .frame(width: Self.tileSize, height: Self.tileSize)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: Self.symbolSize, weight: .semibold))
                    .foregroundStyle(isDark ? color : Color.white)
            }
    }
}

private struct SettingsDetailView: View {
    let pane: SettingsPane

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            selectedView
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationTitle(pane.title)
    }

    @ViewBuilder
    private var selectedView: some View {
        switch pane {
        case .docky:
            ProductSettingsView()
        case .appearanceGeneral:
            AppearanceSettingsView(subsection: .general)
        case .appearanceIndicators:
            AppearanceSettingsView(subsection: .indicators)
        case .appearanceTileLayout:
            AppearanceSettingsView(subsection: .tileLayout)
        case .appearanceWindowShape:
            AppearanceSettingsView(subsection: .windowShape)
        case .appearanceWindowBackground:
            AppearanceSettingsView(subsection: .windowBackground)
        case .appearanceThemes:
            ThemesSettingsView()
        case .appIcons:
            AppIconsSettingsView()
        case .behaviorGeneral:
            BehaviorSettingsView(subsection: .general)
        case .behaviorPlacement:
            BehaviorSettingsView(subsection: .placement)
        case .behaviorVisibility:
            BehaviorSettingsView(subsection: .visibility)
        case .behaviorAppTileClick:
            BehaviorSettingsView(subsection: .appTileClick)
        case .behaviorAppFolders:
            BehaviorSettingsView(subsection: .appFolders)
        case .behaviorWidgets:
            BehaviorSettingsView(subsection: .widgets)
        case .hiddenApps:
            HiddenAppsSettingsView()
        case .launchpad:
            LaunchpadSettingsView()
        case .windowManagement:
            WindowManagementSettingsView()
        case .actions:
            ActionCatalogSettingsView()
        case .behaviorLaunch:
            BehaviorSettingsView(subsection: .launch)
        case .behaviorSystemDock:
            BehaviorSettingsView(subsection: .systemDock)
        case .permissions:
            PermissionsSettingsView()
        case .updates:
            UpdatesSettingsView()
        }
    }
}
