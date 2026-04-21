//
//  WidgetTileView.swift
//  Docky
//

import SwiftUI

struct WidgetTileView: View {
    let tile: WidgetTile
    let usesOuterPadding: Bool

    init(tile: WidgetTile, usesOuterPadding: Bool = true) {
        self.tile = tile
        self.usesOuterPadding = usesOuterPadding
    }

    var body: some View {
        switch tile.kind {
        case .nowPlaying:
            NowPlayingWidgetTileView(tile: tile, usesOuterPadding: usesOuterPadding)
        }
    }
}
