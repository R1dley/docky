//
//  WorkspaceService.swift
//  Docky
//
//  Observes NSWorkspace for live workspace state. First pass: running apps
//  (regular activation policy only — background agents and menu-bar-only
//  apps are filtered out since they don't belong in a dock). Running apps
//  are exposed in a stable order: still-running apps keep their position,
//  newly-launched apps append to the end. Designed to grow: frontmost app,
//  space changes, display changes, etc. can land here as new @Published
//  properties.
//

import AppKit
import ApplicationServices
import Combine
import CoreImage
import CoreMedia
import ScreenCaptureKit

struct RunningApp: Hashable, Identifiable {
    let bundleIdentifier: String
    let localizedName: String
    let processIdentifier: pid_t
    let bundleURL: URL?
    let launchDate: Date?
    let isHidden: Bool

    var id: String { bundleIdentifier }
}

final class WorkspaceService: ObservableObject {
    static let shared = WorkspaceService()

    /// Ordered list: still-running apps keep their position across refreshes,
    /// newly-launched apps append. Terminated apps are removed in place.
    @Published private(set) var runningApps: [RunningApp] = []
    @Published private(set) var minimizedWindows: [AppWindow] = []
    @Published private(set) var minimizedWindowPreviews: [String: NSImage] = [:]
    @Published private(set) var appWindowPreviews: [String: NSImage] = [:]

    private var runningByBundleID: [String: RunningApp] = [:]

    var runningBundleIdentifiers: Set<String> { Set(runningByBundleID.keys) }

    private var observers: [NSObjectProtocol] = []
    private var cancellables: Set<AnyCancellable> = []
    private var attemptedMinimizedWindowPreviewIDs: Set<String> = []
    private var attemptedAppWindowPreviewIDs: Set<String> = []
    private var liveFocusPreviewSession: LiveWindowPreviewSession?

    private init() {
        refresh()
        subscribe()
        subscribeToPermissions()
        subscribeToRegistry()
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        for observer in observers {
            center.removeObserver(observer)
        }
    }

    func isRunning(bundleIdentifier: String) -> Bool {
        runningByBundleID[bundleIdentifier] != nil
    }

    func isHidden(bundleIdentifier: String) -> Bool {
        runningByBundleID[bundleIdentifier]?.isHidden == true
    }

    func minimizedWindowPreview(for window: AppWindow) -> NSImage? {
        minimizedWindowPreviews[window.windowIdentifier]
    }

    func activateOrOpen(bundleIdentifier: String) {
        guard let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else {
            // Not running: launch it.
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                openApplication(at: appURL)
            }
            return
        }

        let accessibilityGranted = PermissionsService.shared.accessibility == .granted
        let allWindows = accessibilityGranted ? appWindows(bundleIdentifier: bundleIdentifier) : []
        let visibleWindows = allWindows.filter { !$0.isMinimized }
        let isFrontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleIdentifier
            && !runningApp.isHidden

        // Running but no AX windows: spawn a new window.
        if accessibilityGranted, allWindows.isEmpty,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            openApplication(at: appURL)
            return
        }

        // Running but every window is minimized: restore the most-recently-minimized.
        if accessibilityGranted, visibleWindows.isEmpty, !allWindows.isEmpty,
           let lastMinimized = minimizedWindows.last(where: { $0.bundleIdentifier == bundleIdentifier }) {
            _ = restoreMinimizedWindow(lastMinimized)
            return
        }

        // Already frontmost with at least one visible window: apply user preference.
        if isFrontmost, !visibleWindows.isEmpty {
            applyFrontmostAppTileClickBehavior(
                runningApp: runningApp,
                visibleWindows: visibleWindows
            )
            return
        }

        // Default: bring the app forward.
        runningApp.unhide()
        runningApp.activate(options: [.activateAllWindows])
    }

    private func applyFrontmostAppTileClickBehavior(
        runningApp: NSRunningApplication,
        visibleWindows: [AppWindow]
    ) {
        let preference = DockyPreferences.shared.appTileFrontmostClickBehavior
        let resolved: AppTileFrontmostClickBehavior = {
            guard preference.requiresPro else { return preference }
            return ProductService.shared.currentTier == .pro ? preference : .none
        }()

        switch resolved {
        case .none:
            return
        case .hide:
            runningApp.hide()
        case .cycleWindows:
            cycleFrontmostAppWindows(visibleWindows)
        case .minimizeAll:
            minimizeAllWindows(visibleWindows)
        }
    }

    private func cycleFrontmostAppWindows(_ visibleWindows: [AppWindow]) {
        // appWindows() returns front-to-back order from AXWindows; raising index 1
        // promotes the next window beneath the frontmost.
        guard visibleWindows.count > 1 else { return }
        _ = focus(window: visibleWindows[1])
    }

    private func minimizeAllWindows(_ visibleWindows: [AppWindow]) {
        for window in visibleWindows {
            _ = minimize(window: window)
        }
    }

    func open(fileURLs: [URL], withApplicationBundleIdentifier bundleIdentifier: String) {
        guard !fileURLs.isEmpty,
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(fileURLs, withApplicationAt: appURL, configuration: configuration) { _, error in
            guard let error else {
                return
            }

            NSLog("[Docky] Failed to open dropped files with app %@: %@ (%@)", bundleIdentifier, fileURLs.map(\.path).joined(separator: ", "), error.localizedDescription)
        }
    }

    func appWindows(bundleIdentifier: String) -> [AppWindow] {
        WindowRegistry.shared.windows(forBundleIdentifier: bundleIdentifier)
    }

    func switchableWindows(forceRefresh: Bool = false) -> [AppWindow] {
        // Registry is event-driven; the cached snapshot is always fresh, so
        // `forceRefresh` is now a no-op kept for source-compat.
        _ = forceRefresh
        return WindowRegistry.shared.visible
    }

    func appWindowPreview(for window: AppWindow) -> NSImage? {
        appWindowPreviews[window.windowIdentifier]
    }

    func liveFocusPreviewImage(for window: AppWindow) async -> NSImage? {
        guard PermissionsService.shared.screenCapture == .granted else {
            return appWindowPreviews[window.windowIdentifier]
        }

        if let cgWindowID = window.cgWindowID,
           let cgImage = CGWindowListCreateImagePrivate(
               .null,
               [.optionIncludingWindow],
               cgWindowID,
               [.boundsIgnoreFraming, .bestResolution]
           ) {
            return makeFullSizeImage(from: cgImage)
        }

        return await captureFullSizeAppWindowImage(for: window) ?? appWindowPreviews[window.windowIdentifier]
    }

    func startLiveFocusPreview(
        for window: AppWindow,
        onFrame: @escaping @MainActor (NSImage?) -> Void
    ) async -> Bool {
        stopLiveFocusPreview()

        guard PermissionsService.shared.screenCapture == .granted else {
            return false
        }

        do {
            let shareableContent = try await shareableContentIncludingOffscreenWindows()
            guard let shareableWindow = matchingShareableWindow(for: window, in: shareableContent.windows) else {
                return false
            }

            let session = LiveWindowPreviewSession(
                shareableWindow: shareableWindow,
                captureSize: fullSizeCaptureSize(for: shareableWindow.frame.size, screenBounds: window.screenBounds),
                onFrame: onFrame
            )
            try await session.start()
            liveFocusPreviewSession = session
            return true
        } catch {
            NSLog("[Docky] Live focus preview stream failed for \(window.windowIdentifier): \(error.localizedDescription)")
            liveFocusPreviewSession = nil
            return false
        }
    }

    func stopLiveFocusPreview() {
        liveFocusPreviewSession?.stop()
        liveFocusPreviewSession = nil
    }

    @discardableResult
    func focus(window: AppWindow) -> Bool {
        WindowRegistry.shared.focus(window)
    }

    func focusApplication(bundleIdentifier: String) {
        guard let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else {
            return
        }

        runningApp.unhide()
        _ = runningApp.activate()
    }

    @discardableResult
    func minimize(window: AppWindow) -> Bool {
        WindowRegistry.shared.minimize(window)
    }

    @discardableResult
    func close(window: AppWindow) -> Bool {
        WindowRegistry.shared.close(window)
    }

    private func openApplication(at appURL: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(
            at: appURL,
            configuration: configuration,
            completionHandler: nil
        )
    }

    func revealApplicationInFinder(bundleIdentifier: String) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([appURL])
    }

    func showAllWindows(bundleIdentifier: String) {
        focusApplication(bundleIdentifier: bundleIdentifier)
    }

    @discardableResult
    func restoreMinimizedWindow(_ window: AppWindow) -> Bool {
        WindowRegistry.shared.focus(window)
    }

    @discardableResult
    func closeMinimizedWindow(_ window: AppWindow) -> Bool {
        WindowRegistry.shared.close(window)
    }

    func hide(bundleIdentifier: String) {
        guard let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else {
            return
        }

        runningApp.hide()
    }

    func quit(bundleIdentifier: String, force: Bool = false) {
        guard let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else {
            return
        }

        if force {
            runningApp.forceTerminate()
        } else {
            runningApp.terminate()
        }
    }

    func refresh() {
        let regular = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        var newMap: [String: RunningApp] = [:]
        for app in regular {
            guard let bundleID = app.bundleIdentifier else { continue }
            newMap[bundleID] = RunningApp(
                bundleIdentifier: bundleID,
                localizedName: app.localizedName ?? bundleID,
                processIdentifier: app.processIdentifier,
                bundleURL: app.bundleURL,
                launchDate: app.launchDate,
                isHidden: app.isHidden
            )
        }

        let ordered = newMap.values.sorted(by: Self.byLaunchDate)

        runningByBundleID = newMap
        runningApps = ordered
        refreshWindowDerivedState()
    }

    /// Oldest → newest. Apps without a launchDate (rare; system apps launched
    /// before our process) are treated as oldest. Bundle identifier is used
    /// as a deterministic tiebreaker.
    nonisolated private static func byLaunchDate(_ lhs: RunningApp, _ rhs: RunningApp) -> Bool {
        switch (lhs.launchDate, rhs.launchDate) {
        case let (l?, r?):
            return l == r
                ? lhs.bundleIdentifier < rhs.bundleIdentifier
                : l < r
        case (nil, _?): return true
        case (_?, nil): return false
        case (nil, nil): return lhs.bundleIdentifier < rhs.bundleIdentifier
        }
    }

    private func subscribe() {
        let center = NSWorkspace.shared.notificationCenter
        let names: [NSNotification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
        ]
        for name in names {
            let token = center.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.refresh()
            }
            observers.append(token)
        }
    }

    private func subscribeToPermissions() {
        PermissionsService.shared.$screenCapture
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshWindowDerivedState()
            }
            .store(in: &cancellables)
    }

    /// Mirrors the registry's window list into the published `minimizedWindows`
    /// array and drives preview captures. Called whenever the registry's
    /// snapshot, the running-apps list, or the screen-capture permission
    /// changes.
    private func subscribeToRegistry() {
        WindowRegistry.shared.$windows
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshWindowDerivedState()
            }
            .store(in: &cancellables)
    }

    private func refreshWindowDerivedState() {
        let registry = WindowRegistry.shared
        let nextMinimized = registry.minimized
        if nextMinimized != minimizedWindows {
            minimizedWindows = nextMinimized
        }
        refreshMinimizedWindowPreviews(for: nextMinimized)
        refreshAppWindowPreviews(for: registry.visible)
    }

    private func refreshMinimizedWindowPreviews(for windows: [AppWindow]) {
        guard PermissionsService.shared.screenCapture == .granted else {
            if !minimizedWindowPreviews.isEmpty {
                minimizedWindowPreviews = [:]
            }
            attemptedMinimizedWindowPreviewIDs = []
            return
        }

        let activeWindowIdentifiers = Set(windows.map(\.windowIdentifier))
        var updatedPreviews = minimizedWindowPreviews
        var didChange = false

        for windowIdentifier in updatedPreviews.keys where !activeWindowIdentifiers.contains(windowIdentifier) {
            updatedPreviews.removeValue(forKey: windowIdentifier)
            didChange = true
        }

        attemptedMinimizedWindowPreviewIDs = attemptedMinimizedWindowPreviewIDs.intersection(activeWindowIdentifiers)

        for window in windows {
            guard updatedPreviews[window.windowIdentifier] == nil,
                  !attemptedMinimizedWindowPreviewIDs.contains(window.windowIdentifier) else {
                continue
            }

            attemptedMinimizedWindowPreviewIDs.insert(window.windowIdentifier)
            captureMinimizedWindowPreviewIfNeeded(for: window)
        }

        if didChange {
            minimizedWindowPreviews = updatedPreviews
        }
    }

    private func captureMinimizedWindowPreviewIfNeeded(for window: AppWindow) {
        Task { [weak self] in
            guard let self,
                  let preview = await self.captureMinimizedWindowPreview(for: window) else {
                return
            }

            guard self.minimizedWindows.contains(where: { $0.windowIdentifier == window.windowIdentifier }),
                  self.minimizedWindowPreviews[window.windowIdentifier] == nil else {
                return
            }

            var updatedPreviews = self.minimizedWindowPreviews
            updatedPreviews[window.windowIdentifier] = preview
            self.minimizedWindowPreviews = updatedPreviews
        }
    }

    private func refreshAppWindowPreviews(for windows: [AppWindow]) {
        guard PermissionsService.shared.screenCapture == .granted else {
            if !appWindowPreviews.isEmpty {
                appWindowPreviews = [:]
            }
            attemptedAppWindowPreviewIDs = []
            return
        }

        let activeWindowIdentifiers = Set(windows.map(\.windowIdentifier))
        var updatedPreviews = appWindowPreviews
        var didChange = false

        for windowIdentifier in updatedPreviews.keys where !activeWindowIdentifiers.contains(windowIdentifier) {
            updatedPreviews.removeValue(forKey: windowIdentifier)
            didChange = true
        }

        attemptedAppWindowPreviewIDs = attemptedAppWindowPreviewIDs.intersection(activeWindowIdentifiers)
        var windowsToCapture: [AppWindow] = []

        for window in windows {
            guard updatedPreviews[window.windowIdentifier] == nil,
                  !attemptedAppWindowPreviewIDs.contains(window.windowIdentifier) else {
                continue
            }

            attemptedAppWindowPreviewIDs.insert(window.windowIdentifier)
            windowsToCapture.append(window)
        }

        if didChange {
            appWindowPreviews = updatedPreviews
        }

        captureAppWindowPreviewsIfNeeded(for: windowsToCapture)
    }

    private func captureAppWindowPreviewsIfNeeded(for windows: [AppWindow]) {
        guard !windows.isEmpty else {
            return
        }

        Task { [weak self] in
            guard let self else { return }

            let shareableContentCache = ShareableContentCache()
            for window in windows {
                guard self.appWindowPreviews[window.windowIdentifier] == nil,
                      let preview = await self.captureAppWindowPreview(
                          for: window,
                          shareableContentCache: shareableContentCache
                      ) else {
                    continue
                }

                guard self.appWindowPreviews[window.windowIdentifier] == nil else {
                    continue
                }

                var updatedPreviews = self.appWindowPreviews
                updatedPreviews[window.windowIdentifier] = preview
                self.appWindowPreviews = updatedPreviews
            }
        }
    }

    private func captureAppWindowPreview(
        for window: AppWindow,
        shareableContentCache: ShareableContentCache? = nil
    ) async -> NSImage? {
        guard PermissionsService.shared.screenCapture == .granted else {
            return nil
        }

        if let windowNumber = window.windowNumber,
           let cgImage = CGWindowListCreateImagePrivate(
               .null,
               [.optionIncludingWindow],
               CGWindowID(windowNumber),
               [.boundsIgnoreFraming, .bestResolution]
           ) {
            return makeThumbnail(from: cgImage, maxSize: CGSize(width: 480, height: 300))
        }

        do {
            let shareableContent: SCShareableContent
            if let shareableContentCache {
                if let cachedContent = shareableContentCache.content {
                    shareableContent = cachedContent
                } else {
                    let fetchedContent = try await shareableContentIncludingOffscreenWindows()
                    shareableContentCache.content = fetchedContent
                    shareableContent = fetchedContent
                }
            } else {
                shareableContent = try await shareableContentIncludingOffscreenWindows()
            }

            guard let shareableWindow = matchingShareableWindow(for: window, in: shareableContent.windows) else {
                NSLog(
                    "[Docky] App window preview: no shareable window for \(window.windowIdentifier) title=\(window.windowTitle) totalShareableWindows=\(shareableContent.windows.count)"
                )
                return nil
            }

            if let cgImage = CGWindowListCreateImagePrivate(
                .null,
                [.optionIncludingWindow],
                shareableWindow.windowID,
                [.boundsIgnoreFraming, .bestResolution]
            ) {
                return makeThumbnail(from: cgImage, maxSize: CGSize(width: 480, height: 300))
            }

            let configuration = SCStreamConfiguration()
            let captureSize = constrainedCaptureSize(for: shareableWindow.frame.size)
            configuration.width = Int(captureSize.width)
            configuration.height = Int(captureSize.height)
            configuration.capturesAudio = false
            configuration.captureMicrophone = false
            configuration.showsCursor = false
            configuration.scalesToFit = true
            configuration.ignoreShadowsSingleWindow = true
            configuration.ignoreGlobalClipSingleWindow = true

            let filter = SCContentFilter(desktopIndependentWindow: shareableWindow)
            let cgImage = try await captureImage(contentFilter: filter, configuration: configuration)
            return makeThumbnail(from: cgImage, maxSize: CGSize(width: 480, height: 300))
        } catch {
            NSLog("[Docky] App window preview capture failed for \(window.windowIdentifier): \(error.localizedDescription)")
            return nil
        }
    }

    private func captureFullSizeAppWindowImage(for window: AppWindow) async -> NSImage? {
        guard PermissionsService.shared.screenCapture == .granted else {
            return nil
        }

        do {
            let shareableContent = try await shareableContentIncludingOffscreenWindows()
            guard let shareableWindow = matchingShareableWindow(for: window, in: shareableContent.windows) else {
                return nil
            }

            let configuration = SCStreamConfiguration()
            let captureSize = fullSizeCaptureSize(for: shareableWindow.frame.size, screenBounds: window.screenBounds)
            configuration.width = Int(captureSize.width)
            configuration.height = Int(captureSize.height)
            configuration.capturesAudio = false
            configuration.captureMicrophone = false
            configuration.showsCursor = false
            configuration.scalesToFit = false
            configuration.ignoreShadowsSingleWindow = true
            configuration.ignoreGlobalClipSingleWindow = true

            let filter = SCContentFilter(desktopIndependentWindow: shareableWindow)
            let cgImage = try await captureImage(contentFilter: filter, configuration: configuration)
            return makeFullSizeImage(from: cgImage)
        } catch {
            NSLog("[Docky] Live focus preview capture failed for \(window.windowIdentifier): \(error.localizedDescription)")
            return nil
        }
    }

    private func captureMinimizedWindowPreview(for window: AppWindow) async -> NSImage? {
        guard PermissionsService.shared.screenCapture == .granted else {
            return nil
        }

        do {
            let shareableContent = try await shareableContentIncludingOffscreenWindows()
            guard let shareableWindow = matchingShareableWindow(for: window, in: shareableContent.windows) else {
                NSLog(
                    "[Docky] Minimized window preview: no shareable window for \(window.windowIdentifier) title=\(window.windowTitle) totalShareableWindows=\(shareableContent.windows.count)"
                )
                return nil
            }

            if let cgImage = CGWindowListCreateImagePrivate(
                .null,
                [.optionIncludingWindow],
                shareableWindow.windowID,
                [.boundsIgnoreFraming, .bestResolution]
            ) {
                return makeThumbnail(from: cgImage, maxSize: CGSize(width: 320, height: 200))
            }

            let configuration = SCStreamConfiguration()
            let captureSize = constrainedCaptureSize(for: shareableWindow.frame.size)
            configuration.width = Int(captureSize.width)
            configuration.height = Int(captureSize.height)
            configuration.capturesAudio = false
            configuration.captureMicrophone = false
            configuration.showsCursor = false
            configuration.scalesToFit = true
            configuration.ignoreShadowsSingleWindow = true
            configuration.ignoreGlobalClipSingleWindow = true

            let filter = SCContentFilter(desktopIndependentWindow: shareableWindow)
            let cgImage = try await captureImage(contentFilter: filter, configuration: configuration)
            return makeThumbnail(from: cgImage, maxSize: CGSize(width: 320, height: 200))
        } catch {
            NSLog("[Docky] Minimized window preview capture failed for \(window.windowIdentifier): \(error.localizedDescription)")
            return nil
        }
    }

    private func matchingShareableWindow(for window: AppWindow, in windows: [SCWindow]) -> SCWindow? {
        if let windowNumber = window.windowNumber,
           let exactMatch = windows.first(where: { Int($0.windowID) == windowNumber }) {
            return exactMatch
        }

        let candidates = windows.filter { shareableWindow in
            guard let owningApplication = shareableWindow.owningApplication else {
                return false
            }

            return owningApplication.processID == window.processIdentifier
                || owningApplication.bundleIdentifier == window.bundleIdentifier
        }

        let titledCandidates = candidates.filter { shareableWindow in
            normalizedWindowTitle(shareableWindow.title) == normalizedWindowTitle(window.windowTitle)
        }

        // Fallback index: position of `window` within its app's window list.
        // The registry maintains stable ordering, so this is consistent across
        // calls within a process run.
        let lookupIndex = WindowRegistry.shared
            .windows(forBundleIdentifier: window.bundleIdentifier)
            .firstIndex(where: { $0.id == window.id }) ?? 0

        if titledCandidates.indices.contains(lookupIndex) {
            return titledCandidates[lookupIndex]
        }

        if let titleMatch = titledCandidates.first {
            return titleMatch
        }

        if candidates.indices.contains(lookupIndex) {
            return candidates[lookupIndex]
        }

        return candidates.first
    }

    private func normalizedWindowTitle(_ title: String?) -> String {
        (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func shareableContentIncludingOffscreenWindows() async throws -> SCShareableContent {
        try await withCheckedThrowingContinuation { continuation in
            SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: false) { content, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let content else {
                    continuation.resume(throwing: NSError(domain: "Docky.WindowPreview", code: -2, userInfo: nil))
                    return
                }

                continuation.resume(returning: content)
            }
        }
    }

    private func constrainedCaptureSize(for sourceSize: CGSize) -> CGSize {
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            return CGSize(width: 320, height: 200)
        }

        let maxSize = CGSize(width: 640, height: 400)
        let scale = min(maxSize.width / sourceSize.width, maxSize.height / sourceSize.height, 1)
        return CGSize(
            width: max(1, floor(sourceSize.width * scale)),
            height: max(1, floor(sourceSize.height * scale))
        )
    }

    private func fullSizeCaptureSize(for sourceSize: CGSize, screenBounds: CGRect?) -> CGSize {
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            return CGSize(width: 1, height: 1)
        }

        let scaleFactor = backingScaleFactor(for: screenBounds)

        return CGSize(
            width: max(1, ceil(sourceSize.width * scaleFactor)),
            height: max(1, ceil(sourceSize.height * scaleFactor))
        )
    }

    private func backingScaleFactor(for screenBounds: CGRect?) -> CGFloat {
        guard let screenBounds else {
            return NSScreen.main?.backingScaleFactor ?? 2
        }

        let bestScreen = NSScreen.screens.max { lhs, rhs in
            intersectionArea(lhs.frame, with: screenBounds) < intersectionArea(rhs.frame, with: screenBounds)
        }

        return bestScreen?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    private func intersectionArea(_ lhs: CGRect, with rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull, !intersection.isEmpty else {
            return 0
        }

        return intersection.width * intersection.height
    }

    private func captureImage(
        contentFilter: SCContentFilter,
        configuration: SCStreamConfiguration
    ) async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            SCScreenshotManager.captureImage(contentFilter: contentFilter, configuration: configuration) { image, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let image else {
                    continuation.resume(throwing: NSError(domain: "Docky.WindowPreview", code: -1, userInfo: nil))
                    return
                }

                continuation.resume(returning: image)
            }
        }
    }

    private func makeThumbnail(from cgImage: CGImage, maxSize: CGSize) -> NSImage? {
        guard cgImage.width > 0, cgImage.height > 0 else {
            return nil
        }

        let sourceSize = CGSize(width: cgImage.width, height: cgImage.height)
        let scale = min(maxSize.width / sourceSize.width, maxSize.height / sourceSize.height, 1)
        let thumbnailSize = CGSize(
            width: max(1, floor(sourceSize.width * scale)),
            height: max(1, floor(sourceSize.height * scale))
        )

        let sourceImage = NSImage(cgImage: cgImage, size: sourceSize)
        let thumbnail = NSImage(size: thumbnailSize)
        thumbnail.lockFocus()
        defer { thumbnail.unlockFocus() }

        NSGraphicsContext.current?.imageInterpolation = .high
        sourceImage.draw(
            in: NSRect(origin: .zero, size: thumbnailSize),
            from: NSRect(origin: .zero, size: sourceSize),
            operation: .copy,
            fraction: 1
        )
        thumbnail.isTemplate = false
        return thumbnail
    }

    private func makeFullSizeImage(from cgImage: CGImage) -> NSImage? {
        guard cgImage.width > 0, cgImage.height > 0 else {
            return nil
        }

        let image = NSImage(
            cgImage: cgImage,
            size: CGSize(width: cgImage.width, height: cgImage.height)
        )
        image.isTemplate = false
        return image
    }

}

private final class ShareableContentCache {
    var content: SCShareableContent?
}

private final class LiveWindowPreviewSession: NSObject, SCStreamOutput {
    private let stream: SCStream
    private let outputQueue = DispatchQueue(label: "Docky.LiveWindowPreview", qos: .userInteractive)
    private let ciContext = CIContext(options: nil)
    private let onFrame: @MainActor (NSImage?) -> Void
    private var isStopped = false

    init(
        shareableWindow: SCWindow,
        captureSize: CGSize,
        onFrame: @escaping @MainActor (NSImage?) -> Void
    ) {
        let configuration = SCStreamConfiguration()
        configuration.width = Int(captureSize.width)
        configuration.height = Int(captureSize.height)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 3
        configuration.capturesAudio = false
        configuration.captureMicrophone = false
        configuration.showsCursor = false
        configuration.scalesToFit = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.ignoreGlobalClipSingleWindow = true

        self.stream = SCStream(
            filter: SCContentFilter(desktopIndependentWindow: shareableWindow),
            configuration: configuration,
            delegate: nil
        )
        self.onFrame = onFrame

        super.init()
    }

    func start() async throws {
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: outputQueue)
        try await stream.startCapture()
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true

        try? stream.removeStreamOutput(self, type: .screen)
        Task {
            try? await stream.stopCapture()
        }
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .screen,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let rect = CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        guard let cgImage = ciContext.createCGImage(ciImage, from: rect) else {
            return
        }

        let image = NSImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))
        image.isTemplate = false

        Task { @MainActor in
            self.onFrame(image)
        }
    }
}
