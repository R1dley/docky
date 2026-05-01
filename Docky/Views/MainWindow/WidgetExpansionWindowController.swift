//
//  WidgetExpansionWindowController.swift
//  Docky
//

import AppKit
import SwiftUI

final class WidgetExpansionWindowController: NSWindowController {
    static let shared = WidgetExpansionWindowController()

    private static let contentPadding: CGFloat = 8

    private var currentTileID: String?
    private var isPreviewHovered = false
    private var isHoldingDockVisible = false
    private weak var heldMainWindow: MainWindow?
    private var pendingDismissTask: Task<Void, Never>?

    private init() {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.level = .mainMenu
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present(
        widget: WidgetTile,
        sourceTileID: String,
        sourceFrame: CGRect,
        cornerRadius: CGFloat,
        renderedSpan: TileSpan
    ) {
        guard let window else { return }

        currentTileID = sourceTileID
        pendingDismissTask?.cancel()
        pendingDismissTask = nil
        beginDockVisibilityHoldIfNeeded()

        let baseTileSize = max(1, min(
            sourceFrame.height,
            sourceFrame.width / CGFloat(max(renderedSpan.rawValue, 1))
        ))
        let extent = widget.kind.expansionExtent
        let size = CGSize(
            width: baseTileSize * CGFloat(extent.widthTiles),
            height: baseTileSize * CGFloat(extent.heightTiles)
        )
        let windowSize = CGSize(
            width: size.width + Self.contentPadding * 2,
            height: size.height + Self.contentPadding * 2
        )

        let rootView = ZStack {
            Color.clear

            WidgetTileView(
                tile: widget,
                cornerRadius: cornerRadius,
                renderedSpan: renderedSpan,
                isWithinStack: false,
                isExpanded: true
            )
            .frame(width: size.width, height: size.height)
            .padding(Self.contentPadding)
        }
        .frame(width: windowSize.width, height: windowSize.height)
        .contentShape(Rectangle())
        .onHover { isHovering in
            WidgetExpansionWindowController.shared.setPreviewHovered(isHovering, sourceTileID: sourceTileID)
        }

        window.contentView = NSHostingView(rootView: rootView)
        window.setContentSize(windowSize)
        window.setFrameOrigin(frameOrigin(for: windowSize, sourceFrame: sourceFrame))
        window.orderFront(nil)
    }

    func dismiss(sourceTileID: String) {
        guard currentTileID == sourceTileID else { return }
        pendingDismissTask?.cancel()
        pendingDismissTask = nil
        isPreviewHovered = false
        endDockVisibilityHoldIfNeeded()
        currentTileID = nil
        close()
    }

    func requestDismiss(sourceTileID: String) {
        guard currentTileID == sourceTileID else { return }
        guard !isPreviewHovered else { return }

        pendingDismissTask?.cancel()
        pendingDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            guard self.currentTileID == sourceTileID, !self.isPreviewHovered else { return }
            self.dismiss(sourceTileID: sourceTileID)
        }
    }

    private func setPreviewHovered(_ isHovered: Bool, sourceTileID: String) {
        guard currentTileID == sourceTileID else { return }
        isPreviewHovered = isHovered

        if isHovered {
            pendingDismissTask?.cancel()
            pendingDismissTask = nil
        } else {
            requestDismiss(sourceTileID: sourceTileID)
        }
    }

    private func beginDockVisibilityHoldIfNeeded() {
        guard !isHoldingDockVisible else { return }
        guard let mainWindow = NSApp.windows.compactMap({ $0 as? MainWindow }).first else { return }

        mainWindow.beginInteraction()
        heldMainWindow = mainWindow
        isHoldingDockVisible = true
    }

    private func endDockVisibilityHoldIfNeeded() {
        guard isHoldingDockVisible else { return }

        heldMainWindow?.endInteraction()
        heldMainWindow = nil
        isHoldingDockVisible = false
    }

    private func frameOrigin(for size: CGSize, sourceFrame: CGRect) -> CGPoint {
        let screen = NSScreen.screens.first { $0.visibleFrame.intersects(sourceFrame) } ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else {
            return CGPoint(x: sourceFrame.midX - size.width / 2, y: sourceFrame.maxY)
        }

        let proposedY = sourceFrame.maxY
        let y = proposedY + size.height <= visibleFrame.maxY
            ? proposedY
            : max(visibleFrame.minY, sourceFrame.minY - size.height)
        let x = min(
            max(sourceFrame.midX - size.width / 2, visibleFrame.minX),
            visibleFrame.maxX - size.width
        )

        return CGPoint(x: x, y: y)
    }
}
