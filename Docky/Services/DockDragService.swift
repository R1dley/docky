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
    /// App folder tile id that has spring-opened due to a sustained hover
    /// during an external drag. Mirrors macOS Finder spring-loaded folders:
    /// hover dwell triggers the popover so the user can drop on a sub-target.
    @Published var springLoadedTileID: String?
    /// Set when the active drag began from inside an app folder popover.
    /// Lets the drop handler remove the app from its source folder before
    /// pinning it at the destination, so dragging an icon out of a folder
    /// onto the dock relocates it instead of duplicating it.
    @Published var sourceFolderTileID: String?
    @Published var sourceFolderBundleIdentifier: String?

    private var springLoadCandidateTileID: String?
    private var springLoadWorkItem: DispatchWorkItem?
    private let springLoadDwell: TimeInterval = 0.7
    private var mouseReleasePoll: DispatchSourceTimer?

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
        self.sourceFolderTileID = nil
        self.sourceFolderBundleIdentifier = nil
        clearSpringLoad()
        cancelMouseReleasePoll()
    }

    /// Polls the global mouse-button state and clears drag state when the
    /// primary button is released. Used by drags that begin OUTSIDE the dock
    /// window (e.g. dragging an icon out of an app folder popover) — the
    /// dock's `draggingEnded(_:)` only fires if the cursor passes through
    /// the dock view, so without this a drag that drops on the desktop or
    /// Finder would leave `kind` non-nil and freeze the dock visible.
    func armMouseReleaseCleanup() {
        cancelMouseReleasePoll()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        var sawPressed = false
        timer.schedule(deadline: .now() + 0.1, repeating: 0.1)
        timer.setEventHandler { [weak self] in
            let pressed = (NSEvent.pressedMouseButtons & 1) != 0
            if pressed {
                sawPressed = true
            } else if sawPressed {
                self?.clear()
            }
        }
        timer.resume()
        mouseReleasePoll = timer
    }

    private func cancelMouseReleasePoll() {
        mouseReleasePoll?.cancel()
        mouseReleasePoll = nil
    }

    /// Schedules a spring-load for `tileID` after a brief dwell. Passing nil
    /// (or repeatedly passing the same id) preserves the candidate; a different
    /// non-nil id resets the timer for the new candidate. The opened popover
    /// stays open until the drag operation ends — close happens via clear().
    func updateSpringLoadCandidate(_ tileID: String?) {
        guard tileID != springLoadCandidateTileID else { return }
        springLoadCandidateTileID = tileID
        springLoadWorkItem?.cancel()
        springLoadWorkItem = nil

        guard let tileID, springLoadedTileID != tileID else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.springLoadCandidateTileID == tileID else { return }
            self.springLoadedTileID = tileID
        }
        springLoadWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + springLoadDwell, execute: work)
    }

    private func clearSpringLoad() {
        springLoadWorkItem?.cancel()
        springLoadWorkItem = nil
        springLoadCandidateTileID = nil
        springLoadedTileID = nil
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
