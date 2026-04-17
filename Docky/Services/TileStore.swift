//
//  TileStore.swift
//  Docky
//
//  Composes the visible dock tile row from three sources:
//    - `persistent-apps`   → pinned apps + spacers (left section)
//    - running apps that aren't pinned → injected between pinned and folders
//    - `persistent-others` → folders + spacers (right section)
//
//  Refresh signals: dock plist change (distributed notification + sandbox
//  file watcher) and workspace running-apps changes.
//

import AppKit
import Combine

final class TileStore: ObservableObject {
    static let shared = TileStore()

    @Published private(set) var tiles: [Tile] = []

    private static let changeNotification = Notification.Name("com.apple.dock.prefchanged")

    private var pinnedTiles: [Tile] = []
    private var otherTiles: [Tile] = []
    /// Currently displayed unpinned running apps, in visual order. May contain
    /// one "ghost" entry at the end — an app that recently exited but sat at
    /// the rightmost position, preserved until something newer takes its slot.
    private var displayedRunning: [RunningApp] = []

    private var notificationObserver: NSObjectProtocol?
    private var fileWatcher: DispatchSourceFileSystemObject?
    private var watchedFileDescriptor: CInt?
    private var cancellables: Set<AnyCancellable> = []

    private init() {
        refresh()
        notificationObserver = DistributedNotificationCenter.default().addObserver(
            forName: Self.changeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
        PermissionsService.shared.$dockPlistURL
            .receive(on: DispatchQueue.main)
            .sink { [weak self] url in
                self?.refresh()
                self?.updateFileWatcher(for: url)
            }
            .store(in: &cancellables)
        WorkspaceService.shared.$runningApps
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildTiles() }
            .store(in: &cancellables)
    }

    deinit {
        if let notificationObserver {
            DistributedNotificationCenter.default().removeObserver(notificationObserver)
        }
        stopFileWatcher()
    }

    func refresh() {
        guard let plist = DockPlistReader.read() else {
            pinnedTiles = []
            otherTiles = []
            rebuildTiles()
            return
        }
        let apps = (plist["persistent-apps"] as? [[String: Any]]) ?? []
        let others = (plist["persistent-others"] as? [[String: Any]]) ?? []
        pinnedTiles = apps.compactMap(Self.parse(entry:))
        otherTiles = others.compactMap(Self.parse(entry:))
        rebuildTiles()
    }

    private static let finderBundleID = "com.apple.finder"

    private func rebuildTiles() {
        let pinnedWithoutFinder = pinnedTiles.filter { !Self.isFinder($0) }
        let pinnedBundleIDs = Self.bundleIdentifiers(in: pinnedWithoutFinder)

        let currentUnpinned = WorkspaceService.shared.runningApps
            .filter { $0.bundleIdentifier != Self.finderBundleID && !pinnedBundleIDs.contains($0.bundleIdentifier) }

        displayedRunning = resolveDisplayedRunning(
            currentUnpinned: currentUnpinned,
            pinnedBundleIDs: pinnedBundleIDs
        )

        let runningTiles = displayedRunning.map(Self.tile(for:))

        var result: [Tile] = [Self.finderTile()]
        result.append(contentsOf: pinnedWithoutFinder)
        if !runningTiles.isEmpty {
            result.append(Tile(id: "divider:running", content: .divider))
        }
        result.append(contentsOf: runningTiles)
        result.append(Tile(id: "divider:trailing", content: .divider))
        result.append(contentsOf: otherTiles)
        result.append(Tile(id: "trash", content: .trash))
        tiles = result
    }

    /// Preserves rightmost-unpinned-app position across exits. Rules:
    ///   - Still-running apps keep their display slot.
    ///   - Newly-launched apps append to the end.
    ///   - A non-rightmost exit drops the tile (shifts remaining left).
    ///   - A rightmost exit holds the slot as a ghost until something newer
    ///     launches to take its place (or the ghost's bundle gets pinned).
    private func resolveDisplayedRunning(
        currentUnpinned: [RunningApp],
        pinnedBundleIDs: Set<String>
    ) -> [RunningApp] {
        let currentMap = Dictionary(
            uniqueKeysWithValues: currentUnpinned.map { ($0.bundleIdentifier, $0) }
        )
        let lastIndex = displayedRunning.count - 1

        var survived: [RunningApp] = []
        var pendingGhost: RunningApp?

        for (index, existing) in displayedRunning.enumerated() {
            if pinnedBundleIDs.contains(existing.bundleIdentifier) {
                continue
            }
            if let live = currentMap[existing.bundleIdentifier] {
                survived.append(live)
            } else if index == lastIndex {
                pendingGhost = existing
            }
        }

        let existingIDs = Set(displayedRunning.map(\.bundleIdentifier))
        for app in currentUnpinned where !existingIDs.contains(app.bundleIdentifier) {
            survived.append(app)
        }

        if let ghost = pendingGhost {
            let ghostLaunch = ghost.launchDate ?? .distantPast
            let hasNewer = survived.contains { app in
                (app.launchDate ?? .distantPast) > ghostLaunch
            }
            if !hasNewer {
                survived.append(ghost)
            }
        }

        return survived
    }

    private static func bundleIdentifiers(in tiles: [Tile]) -> Set<String> {
        var ids: Set<String> = []
        for tile in tiles {
            if case .app(let app) = tile.content, !app.bundleIdentifier.isEmpty {
                ids.insert(app.bundleIdentifier)
            }
        }
        return ids
    }

    private static func isFinder(_ tile: Tile) -> Bool {
        if case .app(let app) = tile.content {
            return app.bundleIdentifier == finderBundleID
        }
        return false
    }

    private static func finderTile() -> Tile {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: finderBundleID)
        let name = url.map { FileManager.default.displayName(atPath: $0.path) } ?? "Finder"
        return Tile(
            id: "pinned:\(finderBundleID)",
            content: .app(AppTile(
                bundleIdentifier: finderBundleID,
                displayName: name
            ))
        )
    }

    // MARK: - Parsing plist entries

    private static func parse(entry: [String: Any]) -> Tile? {
        let tileType = entry["tile-type"] as? String
        let tileData = entry["tile-data"] as? [String: Any] ?? [:]
        let guid = (entry["GUID"] as? NSNumber)?.stringValue ?? UUID().uuidString

        switch tileType {
        case "file-tile":
            return parseAppTile(id: guid, data: tileData)
        case "directory-tile":
            return parseFolderTile(id: guid, data: tileData)
        case "spacer-tile", "small-spacer-tile":
            return Tile(id: guid, content: .spacer)
        default:
            return nil
        }
    }

    private static func parseAppTile(id: String, data: [String: Any]) -> Tile? {
        let label = (data["file-label"] as? String) ?? "Unknown"
        let fileData = data["file-data"] as? [String: Any]
        let urlString = fileData?["_CFURLString"] as? String
        let url = urlString.flatMap { URL(string: $0) }
        let bundleIdentifier = (data["bundle-identifier"] as? String)
            ?? inferBundleIdentifier(from: url)
            ?? ""
        return Tile(id: id, content: .app(AppTile(
            bundleIdentifier: bundleIdentifier,
            displayName: label
        )))
    }

    private static func parseFolderTile(id: String, data: [String: Any]) -> Tile? {
        let label = (data["file-label"] as? String) ?? "Folder"
        let fileData = data["file-data"] as? [String: Any]
        guard let urlString = fileData?["_CFURLString"] as? String,
              let url = URL(string: urlString) else {
            return nil
        }
        return Tile(id: id, content: .folder(FolderTile(url: url, displayName: label)))
    }

    private static func inferBundleIdentifier(from url: URL?) -> String? {
        guard let url else { return nil }
        return Bundle(url: url)?.bundleIdentifier
    }

    // MARK: - Running-but-not-pinned tiles

    private static func tile(for app: RunningApp) -> Tile {
        Tile(
            id: "running:\(app.bundleIdentifier)",
            content: .app(AppTile(
                bundleIdentifier: app.bundleIdentifier,
                displayName: app.localizedName
            ))
        )
    }

    // MARK: - File watcher (sandbox fallback)

    private func updateFileWatcher(for url: URL?) {
        stopFileWatcher()
        guard AppEnvironment.isSandboxed, url != nil else { return }
        PermissionsService.shared.withDockPlistURL { scopedURL in
            guard let scopedURL else { return }
            let fd = open(scopedURL.path, O_EVTONLY)
            guard fd >= 0 else { return }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .extend, .attrib, .rename, .delete],
                queue: .main
            )
            source.setEventHandler { [weak self] in
                guard let self else { return }
                let mask = source.data
                self.refresh()
                if mask.contains(.delete) || mask.contains(.rename) {
                    self.updateFileWatcher(for: PermissionsService.shared.dockPlistURL)
                }
            }
            source.setCancelHandler {
                close(fd)
            }
            watchedFileDescriptor = fd
            fileWatcher = source
            source.resume()
        }
    }

    private func stopFileWatcher() {
        fileWatcher?.cancel()
        fileWatcher = nil
        watchedFileDescriptor = nil
    }
}
