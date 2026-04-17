//
//  WidgetTileView.swift
//  Docky
//

import SwiftUI

struct WidgetTileView: View {
    let tile: WidgetTile

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(.thinMaterial)
            .overlay(
                Text(tile.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .padding(6)
                    .multilineTextAlignment(.center)
            )
    }
}
