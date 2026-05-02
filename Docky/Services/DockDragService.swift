//
//  DockDragService.swift
//  Docky
//
//  Single source of truth for external drag-and-drop into the dock.
//  The NSView-side dragging destination writes drag kind + cursor location.
//  SwiftUI observes and computes the destination index from tile geometry,
//  writing it back so the renderer can splice in a preview tile.
//

import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class DockDragService: ObservableObject {
    static let shared = DockDragService()

    enum Kind: Equatable {
        case app(URL, AppTile)
        case folder(URL, FolderTile)
        case document([URL])
    }

    enum Section: Equatable {
        case pinned, trailing
    }

    @Published var kind: Kind?
    @Published var cursorLocation: CGPoint?
    @Published var destinationIndex: Int?
    @Published var destinationSection: Section?
    @Published var documentTargetTileID: String?

    private init() {}

    func begin(kind: Kind, at location: CGPoint) {
        self.kind = kind
        self.cursorLocation = location
    }

    func updateCursor(_ location: CGPoint) {
        self.cursorLocation = location
    }

    func clear() {
        self.kind = nil
        self.cursorLocation = nil
        self.destinationIndex = nil
        self.destinationSection = nil
        self.documentTargetTileID = nil
    }

    static func resolvePreview(from urls: [URL]) -> Kind? {
        let fileURLs = urls.filter { $0.isFileURL }
        guard !fileURLs.isEmpty else { return nil }

        if let appURL = fileURLs.first(where: isDroppableApp),
           let bundleIdentifier = Bundle(url: appURL)?.bundleIdentifier,
           !bundleIdentifier.isEmpty {
            let displayName = FileManager.default.displayName(atPath: appURL.path)
                .replacingOccurrences(of: ".app", with: "")
            IconCacheService.shared.preloadIcon(forBundleIdentifier: bundleIdentifier, fileURL: appURL)
            return .app(appURL, AppTile(bundleIdentifier: bundleIdentifier, displayName: displayName))
        }
        if let folderURL = fileURLs.first(where: isDroppableFolder) {
            let displayName = FileManager.default.displayName(atPath: folderURL.path)
            return .folder(folderURL, FolderTile(
                url: folderURL,
                displayName: displayName,
                displayMode: .contents
            ))
        }
        return .document(fileURLs)
    }

    private static func isDroppableApp(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        if url.pathExtension.caseInsensitiveCompare("app") == .orderedSame {
            return true
        }
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .typeIdentifierKey])
        guard values?.isDirectory == true, values?.isPackage == true else { return false }
        return values?.typeIdentifier == UTType.application.identifier
    }

    private static func isDroppableFolder(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        return values?.isDirectory == true && values?.isPackage != true
    }
}
