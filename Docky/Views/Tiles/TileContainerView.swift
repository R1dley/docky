//
//  TileContainerView.swift
//  Docky
//

import SwiftUI

struct TileContainerView: View {
    static let edgePadding: CGFloat = 8
    static let dividerWidth: CGFloat = 40
    private let tileMutationAnimation: Animation = .easeInOut(duration: 0.18)

    @ObservedObject private var store = TileStore.shared
    @ObservedObject private var dockSettings = DockSettingsService.shared
    @ObservedObject private var preferences = DockyPreferences.shared

    @State private var draggedPinnedTileID: String?
    @State private var draggedPinnedTileOffset: CGFloat = 0
    @State private var draggedPinnedTileInitialFrame: CGRect?
    @State private var draggedPinnedTileDestinationIndex: Int?
    @State private var pinnedTileFrames: [String: CGRect] = [:]

    private let reorderCoordinateSpaceName = "TileContainerReorderSpace"

    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if position.isVertical {
                    VStack(spacing: preferences.tileSpacing) {
                        tileViews
                    }
                    .padding(.vertical, Self.edgePadding)
                } else {
                    HStack(spacing: preferences.tileSpacing) {
                        tileViews
                    }
                    .padding(.horizontal, Self.edgePadding)
                }
            }

            draggedTileOverlay
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coordinateSpace(name: reorderCoordinateSpaceName)
        .onPreferenceChange(PinnedTileFramePreferenceKey.self) { pinnedTileFrames = $0 }
        .animation(tileMutationAnimation, value: displayTiles)
    }

    @ViewBuilder
    private var tileViews: some View {
        ForEach(displayTiles) { tile in
            let size = Self.size(for: tile, tileSize: dockSettings.tileSize, tileHeight: tileHeight, position: position)
            TileView(tile: tile)
                .frame(width: size.width, height: size.height)
                .opacity(tile.id == draggedPinnedTileID ? 0 : 1)
                .background(alignment: .topLeading) {
                    if isPinnedReorderable(tileID: tile.id) {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: PinnedTileFramePreferenceKey.self,
                                value: [tile.id: proxy.frame(in: .named(reorderCoordinateSpaceName))]
                            )
                        }
                    }
                }
                .gesture(reorderGesture(for: tile.id), including: isPinnedReorderable(tileID: tile.id) ? .gesture : .subviews)
                .transition(tileTransition)
        }
    }

    @ViewBuilder
    private var draggedTileOverlay: some View {
        if let draggedPinnedTile {
            let size = Self.size(for: draggedPinnedTile, tileSize: dockSettings.tileSize, tileHeight: tileHeight, position: position)
            TileView(tile: draggedPinnedTile)
                .frame(width: size.width, height: size.height)
                .position(draggedTilePosition)
                .offset(axisSize(value: draggedPinnedTileOffset))
                .zIndex(10)
                .allowsHitTesting(false)
        }
    }

    private var displayTiles: [Tile] {
        let previewPinnedIDs = previewPinnedTileIDs
        guard !previewPinnedIDs.isEmpty else {
            return store.tiles
        }

        let pinnedTilesByID = Dictionary(uniqueKeysWithValues: store.tiles.compactMap { tile in
            isPinnedReorderable(tileID: tile.id) ? (tile.id, tile) : nil
        })

        var result: [Tile] = []
        var insertedPinnedTiles = false

        for tile in store.tiles {
            if isPinnedReorderable(tileID: tile.id) {
                if !insertedPinnedTiles {
                    result.append(contentsOf: previewPinnedIDs.compactMap { pinnedTilesByID[$0] })
                    insertedPinnedTiles = true
                }
                continue
            }

            result.append(tile)
        }

        return result
    }

    private var pinnedTileIDs: [String] {
        store.tiles.filter { isPinnedReorderable(tileID: $0.id) }.map(\.id)
    }

    private var previewPinnedTileIDs: [String] {
        guard let draggedPinnedTileID,
              let destinationIndex = draggedPinnedTileDestinationIndex else {
            return pinnedTileIDs
        }

        var remainingPinnedTileIDs = pinnedTileIDs.filter { $0 != draggedPinnedTileID }
        let clampedDestinationIndex = min(max(destinationIndex, 0), remainingPinnedTileIDs.count)
        remainingPinnedTileIDs.insert(draggedPinnedTileID, at: clampedDestinationIndex)
        return remainingPinnedTileIDs
    }

    private var draggedPinnedTile: Tile? {
        guard let draggedPinnedTileID else {
            return nil
        }

        return store.tiles.first { $0.id == draggedPinnedTileID }
    }

    private var draggedTilePosition: CGPoint {
        guard let frame = draggedPinnedTileInitialFrame else {
            return .zero
        }

        return CGPoint(x: frame.midX, y: frame.midY)
    }

    private var tileTransition: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.9, anchor: tileScaleAnchor).combined(with: .opacity),
            removal: .scale(scale: 0.9, anchor: tileScaleAnchor).combined(with: .opacity)
        )
    }

    private var tileScaleAnchor: UnitPoint {
        switch position {
        case .top:
            .top
        case .left:
            .leading
        case .right:
            .trailing
        case .bottom:
            .bottom
        }
    }

    private var tileHeight: CGFloat {
        let iconHeight = dockSettings.magnification ? dockSettings.largeSize : dockSettings.tileSize
        return iconHeight + preferences.tileVerticalPadding * 2
    }

    private var position: ResolvedDockWindowPosition {
        preferences.windowPosition.resolved(systemOrientation: dockSettings.orientation)
    }

    private func isPinnedReorderable(tileID: String) -> Bool {
        store.isPinnedReorderable(tileID: tileID)
    }

    private func reorderGesture(for tileID: String) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(reorderCoordinateSpaceName))
            .onChanged { value in
                updateDrag(for: tileID, value: value)
            }
            .onEnded { value in
                endDrag(for: tileID, value: value)
            }
    }

    private func updateDrag(for tileID: String, value: DragGesture.Value) {
        guard isPinnedReorderable(tileID: tileID) else {
            return
        }

        if draggedPinnedTileID == nil {
            draggedPinnedTileID = tileID
            draggedPinnedTileInitialFrame = pinnedTileFrames[tileID]
            draggedPinnedTileDestinationIndex = pinnedTileIDs.firstIndex(of: tileID)
        }

        guard draggedPinnedTileID == tileID else {
            return
        }

        draggedPinnedTileOffset = projected(size: value.translation)
        updatePreviewDestination(at: projected(point: value.location), draggedTileID: tileID)
    }

    private func endDrag(for tileID: String, value: DragGesture.Value) {
        updateDrag(for: tileID, value: value)

        guard draggedPinnedTileID == tileID else {
            clearDragState()
            return
        }

        let finalPinnedTileIDs = previewPinnedTileIDs
        let didChangeOrder = finalPinnedTileIDs != pinnedTileIDs

        if didChangeOrder {
            _ = DockEditorService.shared.setPinnedItemOrder(ids: finalPinnedTileIDs)
        }

        withAnimation(tileMutationAnimation) {
            clearDragState()
        }
    }

    private func updatePreviewDestination(at positionValue: CGFloat, draggedTileID: String) {
        let visiblePinnedTileIDs = previewPinnedTileIDs.filter { $0 != draggedTileID }
        guard !visiblePinnedTileIDs.isEmpty else {
            draggedPinnedTileDestinationIndex = 0
            return
        }

        let destinationIndex = visiblePinnedTileIDs.enumerated().first { _, tileID in
            guard let frame = pinnedTileFrames[tileID] else {
                return false
            }
            let midpoint = projected(point: frame.origin) + projected(size: frame.size) / 2
            return positionValue < midpoint
        }?.offset ?? visiblePinnedTileIDs.count

        guard draggedPinnedTileDestinationIndex != destinationIndex else {
            return
        }

        withAnimation(tileMutationAnimation) {
            draggedPinnedTileDestinationIndex = destinationIndex
        }
    }

    private func clearDragState() {
        draggedPinnedTileID = nil
        draggedPinnedTileOffset = 0
        draggedPinnedTileInitialFrame = nil
        draggedPinnedTileDestinationIndex = nil
    }

    private func projected(size: CGSize) -> CGFloat {
        position.isVertical ? size.height : size.width
    }

    private func projected(point: CGPoint) -> CGFloat {
        position.isVertical ? point.y : point.x
    }

    private func axisSize(value: CGFloat) -> CGSize {
        position.isVertical ? CGSize(width: 0, height: value) : CGSize(width: value, height: 0)
    }

    static func size(
        for tile: Tile,
        tileSize: CGFloat,
        tileHeight: CGFloat,
        position: ResolvedDockWindowPosition
    ) -> CGSize {
        switch (position.isVertical, tile.content) {
        case (false, .divider):
            CGSize(width: dividerWidth, height: tileHeight)
        case (false, _):
            CGSize(width: tileSize, height: tileHeight)
        case (true, .divider):
            CGSize(width: tileHeight, height: dividerWidth)
        case (true, _):
            CGSize(width: tileHeight, height: tileSize)
        }
    }

    /// Total content size for the given tile list, including inter-tile spacing
    /// and outer stack padding. Used by MainWindow to size itself to fit.
    static func contentSize(
        tiles: [Tile],
        tileSize: CGFloat,
        tileHeight: CGFloat,
        tileSpacing: CGFloat,
        position: ResolvedDockWindowPosition
    ) -> CGSize {
        let sizes = tiles.map { size(for: $0, tileSize: tileSize, tileHeight: tileHeight, position: position) }
        let spacings = max(0, CGFloat(tiles.count) - 1) * tileSpacing

        if position.isVertical {
            let height = sizes.reduce(CGFloat(0)) { $0 + $1.height } + spacings + edgePadding * 2
            let width = sizes.map(\.width).max() ?? tileSize
            return CGSize(width: width, height: height)
        }

        let width = sizes.reduce(CGFloat(0)) { $0 + $1.width } + spacings + edgePadding * 2
        let height = sizes.map(\.height).max() ?? tileHeight
        return CGSize(width: width, height: height)
    }
}

private struct PinnedTileFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
