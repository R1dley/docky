//
//  TilePressService.swift
//  Docky
//
//  Tracks which dock tile is currently being pressed (mouse-down before
//  release) using a single NSEvent local monitor instead of a SwiftUI
//  gesture. The previous gesture-based tracker conflicted with the parent
//  reorder gesture and prevented tile drag; observing at the AppKit event
//  layer side-steps SwiftUI's gesture-claim contest entirely — local
//  monitors return the event unchanged so normal dispatch still happens.
//

import AppKit
import Combine
import Foundation

@MainActor
final class TilePressService: ObservableObject {
    static let shared = TilePressService()

    @Published private(set) var pressedTileID: String?

    private var monitor: Any?
    private var tileFrames: [String: CGRect] = [:]

    private init() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    /// Registers the latest screen-coordinate frame for `tileID`. TileView
    /// already tracks this for hover-preview anchoring; we reuse it for
    /// press hit-testing.
    func registerFrame(tileID: String, globalFrame: CGRect) {
        tileFrames[tileID] = globalFrame
    }

    func unregisterFrame(tileID: String) {
        tileFrames.removeValue(forKey: tileID)
        if pressedTileID == tileID {
            pressedTileID = nil
        }
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            let location = NSEvent.mouseLocation
            let hit = tileFrames.first { _, frame in frame.contains(location) }
            pressedTileID = hit?.key
        case .leftMouseUp:
            if pressedTileID != nil {
                pressedTileID = nil
            }
        default:
            break
        }
    }
}
