//
//  TileContainerView.swift
//  Docky
//

import SwiftUI

struct TileContainerView: View {
    static let horizontalPadding: CGFloat = 8
    static let dividerWidth: CGFloat = 20

    @ObservedObject private var store = TileStore.shared
    @ObservedObject private var dockSettings = DockSettingsService.shared
    @ObservedObject private var preferences = DockyPreferences.shared

    var body: some View {
        HStack(spacing: preferences.tileSpacing) {
            ForEach(store.tiles) { tile in
                TileView(tile: tile)
                    .frame(
                        width: Self.width(for: tile, tileSize: dockSettings.tileSize),
                        height: dockSettings.tileSize
                    )
            }
        }
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.vertical, preferences.tileVerticalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    static func width(for tile: Tile, tileSize: CGFloat) -> CGFloat {
        switch tile.content {
        case .divider: return dividerWidth
        default: return tileSize
        }
    }

    /// Total content width for the given tile list at `tileSize`, including
    /// inter-tile spacing and horizontal padding. Used by MainWindow to
    /// size itself to fit.
    static func contentWidth(tiles: [Tile], tileSize: CGFloat, tileSpacing: CGFloat) -> CGFloat {
        let tileWidths = tiles.reduce(CGFloat(0)) { $0 + width(for: $1, tileSize: tileSize) }
        let spacings = max(0, CGFloat(tiles.count) - 1) * tileSpacing
        return tileWidths + spacings + horizontalPadding * 2
    }
}
