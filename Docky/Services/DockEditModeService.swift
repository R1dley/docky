//
//  DockEditModeService.swift
//  Docky
//

import Combine
import Foundation
import CoreGraphics

enum DockEditPaletteItem: Equatable, Identifiable {
    case spacer
    case divider
    case widget(ownerBundleIdentifier: String, kind: WidgetKind)
    case smartStack

    var id: String {
        switch self {
        case .spacer:
            "spacer"
        case .divider:
            "divider"
        case .widget(let ownerBundleIdentifier, let kind):
            "widget:\(ownerBundleIdentifier):\(kind.rawValue)"
        case .smartStack:
            "smart-stack"
        }
    }
}

struct DockEditPaletteDrag: Equatable {
    let item: DockEditPaletteItem
    let location: CGPoint
}

final class DockEditModeService: ObservableObject {
    static let shared = DockEditModeService()

    @Published private(set) var isActive = false
    @Published private(set) var paletteDrag: DockEditPaletteDrag?
    @Published var paletteDropDestinationIndex: Int?

    private init() {}

    func enter() {
        isActive = true
    }

    func exit() {
        isActive = false
        endPaletteDrag()
    }

    func toggle() {
        isActive ? exit() : enter()
    }

    func updatePaletteDrag(item: DockEditPaletteItem, location: CGPoint) {
        isActive = true
        paletteDrag = DockEditPaletteDrag(item: item, location: location)
    }

    func beginPaletteDrag(item: DockEditPaletteItem) {
        isActive = true
        paletteDrag = DockEditPaletteDrag(item: item, location: .zero)
    }

    func endPaletteDrag() {
        paletteDrag = nil
        paletteDropDestinationIndex = nil
    }
}
