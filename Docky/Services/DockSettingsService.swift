//
//  DockSettingsService.swift
//  Docky
//
//  Reads system Dock preferences (com.apple.dock) and republishes them.
//
//  Two read paths, selected at runtime:
//   1. Bookmarked com.apple.dock.plist URL (PermissionsService.dockPlistURL).
//      Used whenever a user-selected file is available. Required under
//      the App Sandbox because CFPreferences can't cross domains there.
//   2. CFPreferencesCopyAppValue on com.apple.dock. Used only for
//      unsandboxed Docky without a bookmark (works via cfprefsd).
//

import AppKit
import Combine

final class DockSettingsService: ObservableObject {
    static let shared = DockSettingsService()

    enum Orientation: String {
        case bottom, left, right
    }

    enum MinimizeEffect: String {
        case genie, scale, suck
    }

    @Published private(set) var orientation: Orientation = .bottom
    @Published private(set) var tileSize: CGFloat = 48
    @Published private(set) var largeSize: CGFloat = 64
    @Published private(set) var magnification: Bool = false
    @Published private(set) var autohide: Bool = false
    @Published private(set) var autohideDelay: TimeInterval = 0.5
    @Published private(set) var autohideTimeModifier: Double = 1.0
    @Published private(set) var minimizeEffect: MinimizeEffect = .genie
    @Published private(set) var minimizeToApplication: Bool = false
    @Published private(set) var showRecents: Bool = true
    @Published private(set) var showProcessIndicators: Bool = true

    private static let changeNotification = Notification.Name("com.apple.dock.prefchanged")

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
    }

    deinit {
        if let notificationObserver {
            DistributedNotificationCenter.default().removeObserver(notificationObserver)
        }
        stopFileWatcher()
    }

    /// Sandbox fallback: when `DistributedNotificationCenter` may not deliver
    /// `com.apple.dock.prefchanged`, watch the bookmarked plist for changes.
    /// No-op in unsandboxed mode (the distributed notification is sufficient).
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

    func refresh() {
        guard let values = DockPlistReader.read() else { return }
        applyValues(values)
    }

    private func applyValues(_ values: [String: Any]) {
        if let raw = values["orientation"] as? String, let value = Orientation(rawValue: raw) {
            orientation = value
        }
        if let value = (values["tilesize"] as? NSNumber)?.doubleValue {
            tileSize = CGFloat(value)
        }
        if let value = (values["largesize"] as? NSNumber)?.doubleValue {
            largeSize = CGFloat(value)
        }
        if let value = (values["magnification"] as? NSNumber)?.boolValue {
            magnification = value
        }
        if let value = (values["autohide"] as? NSNumber)?.boolValue {
            autohide = value
        }
        if let value = (values["autohide-delay"] as? NSNumber)?.doubleValue {
            autohideDelay = value
        }
        if let value = (values["autohide-time-modifier"] as? NSNumber)?.doubleValue {
            autohideTimeModifier = value
        }
        if let raw = values["mineffect"] as? String, let value = MinimizeEffect(rawValue: raw) {
            minimizeEffect = value
        }
        if let value = (values["minimize-to-application"] as? NSNumber)?.boolValue {
            minimizeToApplication = value
        }
        if let value = (values["show-recents"] as? NSNumber)?.boolValue {
            showRecents = value
        }
        if let value = (values["show-process-indicators"] as? NSNumber)?.boolValue {
            showProcessIndicators = value
        }
    }
}
