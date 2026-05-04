//
//  MainWindow.swift
//  Docky
//
//  Created by Jose Quintero on 17/04/26.
//

import AppKit
import Combine
import SwiftUI

final class MainWindowContainerView: NSView {
    static let contentPadding: CGFloat = 2

    private let contentView = ClickThroughHostingView(rootView: MainWindowView())
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)

        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: topAnchor, constant: Self.contentPadding),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.contentPadding),
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.contentPadding),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.contentPadding),
        ])
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        (window as? MainWindow)?.pointerDidEnterWindow()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        (window as? MainWindow)?.pointerDidExitWindow()
    }
}

final class MainWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override var level: NSWindow.Level { get { .mainMenu } set {} }

    private enum VisibilityState {
        case visible
        case hidden
    }

    private let backgroundBlurRadius = 10
    private let hiddenRevealThickness: CGFloat = 2
    private let baseAutohideAnimationDuration: TimeInterval = 0.22
    private let tileMutationAnimationDuration: TimeInterval = 0.18
    private let dockSettings = DockSettingsService.shared
    private let preferences = DockyPreferences.shared
    private let layout = DockLayoutService.shared
    private let tileStore = TileStore.shared
    private let editMode = DockEditModeService.shared
    private let minimumWidth: CGFloat = 120
    private var cancellables: Set<AnyCancellable> = []
    private var hideWorkItem: DispatchWorkItem?
    private var fullscreenRecheckWorkItem: DispatchWorkItem?
    private var fullscreenRevealWorkItem: DispatchWorkItem?
    private var globalPointerMonitor: Any?
    private var localPointerMonitor: Any?
    private var globalDragRevealMonitor: Any?
    private var localDragRevealMonitor: Any?
    private var isPointerInsideWindow = false
    private var activeInteractionCount = 0
    private var visibilityState: VisibilityState
    private var hasCompletedSetup = false
    private var hasResolvedInitialFrame = false
    private var lastPointerScreenFrame: CGRect?
    private var isFullscreenActiveOnTargetScreen = false

    private var effectivelyAutohides: Bool {
        preferences.autohidesWindow || isFullscreenActiveOnTargetScreen
    }

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        visibilityState = DockyPreferences.shared.autohidesWindow ? .hidden : .visible
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        performSetupIfNeeded()
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        applyCurrentFrame(animated: false)
    }

    private func performSetupIfNeeded() {
        guard !hasCompletedSetup else { return }
        hasCompletedSetup = true

        backgroundColor = .clear
        isOpaque = false
        isMovableByWindowBackground = false
        alphaValue = 0
        applyCollectionBehavior()
        observeFrameInputs()
        observeScreenAndSpaceInputs()
        observeWindowPlacementInputs()
        observeVisibilityInputs()
        updatePointerScreenMonitoring()
        updateDragRevealMonitoring()
        isFullscreenActiveOnTargetScreen = computeFullscreenStateOnTargetScreen()
        if isFullscreenActiveOnTargetScreen {
            visibilityState = shouldRemainVisible ? .visible : .hidden
        }
    }

    deinit {
        fullscreenRecheckWorkItem?.cancel()
        fullscreenRevealWorkItem?.cancel()
        if let globalPointerMonitor {
            NSEvent.removeMonitor(globalPointerMonitor)
        }
        if let localPointerMonitor {
            NSEvent.removeMonitor(localPointerMonitor)
        }
        if let globalDragRevealMonitor {
            NSEvent.removeMonitor(globalDragRevealMonitor)
        }
        if let localDragRevealMonitor {
            NSEvent.removeMonitor(localDragRevealMonitor)
        }
    }

    override func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
        super.order(place, relativeTo: otherWin)
        applyBackgroundBlur()
    }

    private func applyBackgroundBlur() {
        guard windowNumber > 0 else { return }
        _ = CGSSetWindowBackgroundBlurRadius(
            CGSMainConnectionID(),
            windowNumber,
            backgroundBlurRadius
        )
    }

    private func observeFrameInputs() {
        let layoutSignals: [AnyPublisher<Void, Never>] = [
            dockSettings.$orientation.map { _ in () }.eraseToAnyPublisher(),
            dockSettings.$tileSize.map { _ in () }.eraseToAnyPublisher(),
            dockSettings.$largeSize.map { _ in () }.eraseToAnyPublisher(),
            dockSettings.$magnification.map { _ in () }.eraseToAnyPublisher(),
            preferences.$tileVerticalPadding.map { _ in () }.eraseToAnyPublisher(),
            preferences.$tileSpacing.map { _ in () }.eraseToAnyPublisher(),
            preferences.$overflowBehavior.map { _ in () }.eraseToAnyPublisher(),
            preferences.$windowAxisSizing.map { _ in () }.eraseToAnyPublisher(),
            preferences.$windowPosition.map { _ in () }.eraseToAnyPublisher(),
            preferences.$windowDisplayTarget.map { _ in () }.eraseToAnyPublisher(),
            editMode.$paletteDrag.map { _ in () }.eraseToAnyPublisher(),
            editMode.$paletteDropDestination.map { _ in () }.eraseToAnyPublisher(),
            DockDragService.shared.$kind.map { _ in () }.eraseToAnyPublisher(),
            DockDragService.shared.$documentTargetTileID.map { _ in () }.eraseToAnyPublisher(),
            DockDragService.shared.$destinationIndex.map { _ in () }.eraseToAnyPublisher(),
            DockDragService.shared.$destinationSection.map { _ in () }.eraseToAnyPublisher(),
        ]
        Publishers.MergeMany(layoutSignals)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyCurrentFrame(animated: true, duration: self?.tileMutationAnimationDuration) }
            .store(in: &cancellables)

        tileStore.$tiles
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyCurrentFrame(animated: true, duration: self?.tileMutationAnimationDuration) }
            .store(in: &cancellables)

        editMode.$isActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isActive in
                guard let self else { return }
                if isActive {
                    self.hideWorkItem?.cancel()
                    self.setVisibility(.visible, animated: true)
                } else {
                    self.scheduleHideIfNeeded()
                }
            }
            .store(in: &cancellables)

    }

    private func observeScreenAndSpaceInputs() {
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyCurrentFrame(animated: false)
                self?.updateFullscreenStateAndApply(animated: false)
            }
            .store(in: &cancellables)

        let workspaceCenter = NSWorkspace.shared.notificationCenter

        workspaceCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyCurrentFrame(animated: false)
                self?.updateFullscreenStateAndApply(animated: true)
                // The space change fires during the fullscreen exit animation
                // while the fullscreen window is still on-screen. Re-check once
                // the animation has had time to complete.
                self?.scheduleFullscreenRecheck()
            }
            .store(in: &cancellables)

        workspaceCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateFullscreenStateAndApply(animated: true)
            }
            .store(in: &cancellables)
    }

    private func observeWindowPlacementInputs() {
        preferences.$windowSpaceBehavior
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyCollectionBehavior()
            }
            .store(in: &cancellables)

        preferences.$windowDisplayTarget
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.lastPointerScreenFrame = nil
                self?.updatePointerScreenMonitoring()
                self?.updateFullscreenStateAndApply(animated: true)
            }
            .store(in: &cancellables)

        PermissionsService.shared.$accessibility
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.lastPointerScreenFrame = nil
                self?.updatePointerScreenMonitoring()
            }
            .store(in: &cancellables)
    }

    private func observeVisibilityInputs() {
        preferences.$autohidesWindow
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyEffectiveVisibility(animated: true)
            }
            .store(in: &cancellables)
    }

    private func applyCollectionBehavior() {
        collectionBehavior = preferences.windowSpaceBehavior.collectionBehavior(includesFullScreenAuxiliary: true)
    }

    private func updatePointerScreenMonitoring() {
        if let globalPointerMonitor {
            NSEvent.removeMonitor(globalPointerMonitor)
            self.globalPointerMonitor = nil
        }
        if let localPointerMonitor {
            NSEvent.removeMonitor(localPointerMonitor)
            self.localPointerMonitor = nil
        }

        guard preferences.windowDisplayTarget == .displayContainingPointer else { return }

        let pointerEvents: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel]
        if PermissionsService.shared.accessibility == .granted {
            globalPointerMonitor = NSEvent.addGlobalMonitorForEvents(matching: pointerEvents) { [weak self] _ in
                self?.handlePointerScreenChangeIfNeeded()
            }
        }
        localPointerMonitor = NSEvent.addLocalMonitorForEvents(matching: pointerEvents) { [weak self] event in
            self?.handlePointerScreenChangeIfNeeded()
            return event
        }
    }

    private func updateDragRevealMonitoring() {
        if let globalDragRevealMonitor {
            NSEvent.removeMonitor(globalDragRevealMonitor)
            self.globalDragRevealMonitor = nil
        }
        if let localDragRevealMonitor {
            NSEvent.removeMonitor(localDragRevealMonitor)
            self.localDragRevealMonitor = nil
        }

        let dragEvents: NSEvent.EventTypeMask = [.leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        globalDragRevealMonitor = NSEvent.addGlobalMonitorForEvents(matching: dragEvents) { [weak self] _ in
            self?.syncPointerPresenceForDragSession()
        }
        localDragRevealMonitor = NSEvent.addLocalMonitorForEvents(matching: dragEvents) { [weak self] event in
            self?.syncPointerPresenceForDragSession()
            return event
        }
    }

    private func handlePointerScreenChangeIfNeeded() {
        guard preferences.windowDisplayTarget == .displayContainingPointer else { return }
        let nextScreenFrame = targetScreen()?.frame
        guard nextScreenFrame != lastPointerScreenFrame else { return }
        lastPointerScreenFrame = nextScreenFrame
        DispatchQueue.main.async { [weak self] in
            self?.applyCurrentFrame(animated: false)
            self?.updateFullscreenStateAndApply(animated: true)
        }
    }

    func pointerDidEnterWindow() {
        isPointerInsideWindow = true
        hideWorkItem?.cancel()

        guard effectivelyAutohides else { return }

        if shouldDwellBeforeReveal {
            scheduleFullscreenReveal()
            return
        }

        setVisibility(.visible, animated: true)
    }

    func pointerDidExitWindow() {
        isPointerInsideWindow = false
        fullscreenRevealWorkItem?.cancel()
        fullscreenRevealWorkItem = nil
        scheduleHideIfNeeded()
    }

    private var shouldDwellBeforeReveal: Bool {
        isFullscreenActiveOnTargetScreen
            && visibilityState == .hidden
            && preferences.fullscreenRevealDelay > 0
    }

    private func scheduleFullscreenReveal() {
        fullscreenRevealWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.isPointerInsideWindow,
                  self.effectivelyAutohides
            else { return }
            self.setVisibility(.visible, animated: true)
        }
        fullscreenRevealWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + preferences.fullscreenRevealDelay, execute: workItem)
    }

    private func syncPointerPresenceForDragSession() {
        let containsPointer = frame.contains(NSEvent.mouseLocation)
        if containsPointer, !isPointerInsideWindow {
            pointerDidEnterWindow()
        } else if !containsPointer, isPointerInsideWindow {
            pointerDidExitWindow()
        }
    }

    func beginInteraction() {
        activeInteractionCount += 1
        hideWorkItem?.cancel()

        guard effectivelyAutohides else { return }
        setVisibility(.visible, animated: true)
    }

    func endInteraction() {
        activeInteractionCount = max(0, activeInteractionCount - 1)
        scheduleHideIfNeeded()
    }

    private func applyEffectiveVisibility(animated: Bool) {
        hideWorkItem?.cancel()

        if effectivelyAutohides {
            let nextState: VisibilityState = shouldRemainVisible ? .visible : .hidden
            setVisibility(nextState, animated: animated)
            return
        }

        setVisibility(.visible, animated: animated)
    }

    private func scheduleHideIfNeeded() {
        hideWorkItem?.cancel()

        guard effectivelyAutohides, !shouldRemainVisible else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.shouldRemainVisible else { return }
            self.setVisibility(.hidden, animated: true)
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + preferences.autohideWindowDelay, execute: workItem)
    }

    private var shouldRemainVisible: Bool {
        isPointerInsideWindow || activeInteractionCount > 0 || editMode.isActive
    }

    private func setVisibility(_ state: VisibilityState, animated: Bool) {
        if state == .visible {
            fullscreenRevealWorkItem?.cancel()
            fullscreenRevealWorkItem = nil
        }

        guard visibilityState != state else {
            applyCurrentFrame(animated: false)
            return
        }

        visibilityState = state
        applyCurrentFrame(animated: animated)
    }

    private func applyCurrentFrame(animated: Bool) {
        applyCurrentFrame(animated: animated, duration: nil)
    }

    private func applyCurrentFrame(animated: Bool, duration: TimeInterval?) {
        let screenBounds = targetScreen()?.frame ?? screen?.frame ?? NSScreen.main?.frame ?? .zero
        lastPointerScreenFrame = screenBounds
        let contentPadding = MainWindowContainerView.contentPadding
        let position = preferences.windowPosition.resolved(systemOrientation: dockSettings.orientation)
        let baseTileSize = dockSettings.displayTileSize
        let baseTileHeight = baseTileSize + preferences.tileVerticalPadding * 2
        let externalAppDropPreview: AppTile? = {
            if case let .app(_, tile) = DockDragService.shared.kind { return tile }
            return nil
        }()
        let externalFolderDropPreview: FolderTile? = {
            // Only grow the chrome when there's an actual placement: cursor in the
            // trailing drop region with a resolved insertion index. Open-with mode
            // (over an app tile) and idle hovering both leave chrome unchanged.
            guard DockDragService.shared.documentTargetTileID == nil,
                  DockDragService.shared.destinationSection == .trailing,
                  DockDragService.shared.destinationIndex != nil,
                  case let .folder(_, tile) = DockDragService.shared.kind else {
                return nil
            }
            return tile
        }()
        let sizingTiles = TileContainerView.previewedTiles(
            from: tileStore.tiles,
            paletteDrag: editMode.paletteDrag,
            paletteDropDestination: editMode.paletteDropDestination,
            externalAppDropPreview: externalAppDropPreview,
            externalFolderDropPreview: externalFolderDropPreview
        )
        let naturalContentSize = TileContainerView.contentSize(
            tiles: sizingTiles,
            tileSize: baseTileSize,
            tileHeight: baseTileHeight,
            tileSpacing: preferences.tileSpacing,
            position: position
        )
        let unreservedAvailableAxisLength = max(
            0,
            axisLength(of: screenBounds.size, position: position) - contentPadding * 2
        )
        let contentAvailableAxisLength = max(
            0,
            unreservedAvailableAxisLength
                - (shouldReserveStatusBarLength(
                    for: naturalContentSize,
                    availableAxisLength: unreservedAvailableAxisLength,
                    position: position
                ) ? reservedStatusBarLength : 0)
        )
        let availableAxisLength = preferences.windowAxisSizing == .fullAxis
            ? unreservedAvailableAxisLength
            : contentAvailableAxisLength
        let compactsWidgetsForOverflow = shouldCompactWidgetsForOverflow(
            contentSize: naturalContentSize,
            availableAxisLength: availableAxisLength,
            position: position
        )
        let baseContentSize = TileContainerView.contentSize(
            tiles: sizingTiles,
            tileSize: baseTileSize,
            tileHeight: baseTileHeight,
            tileSpacing: preferences.tileSpacing,
            position: position,
            compactWidgets: compactsWidgetsForOverflow
        )
        let contentScale = overflowContentScale(
            for: baseContentSize,
            availableAxisLength: availableAxisLength,
            position: position
        )
        layout.setContentScale(contentScale)
        layout.setCompactsWidgetsForOverflow(compactsWidgetsForOverflow)

        let scaledTileSize = baseTileSize * contentScale
        let scaledTileHeight = scaledTileSize + (preferences.tileVerticalPadding * contentScale * 2)
        let scaledTileSpacing = preferences.tileSpacing * contentScale
        let displayedContentSize = TileContainerView.contentSize(
            tiles: sizingTiles,
            tileSize: scaledTileSize,
            tileHeight: scaledTileHeight,
            tileSpacing: scaledTileSpacing,
            position: position,
            compactWidgets: compactsWidgetsForOverflow,
            edgePadding: TileContainerView.edgePadding * contentScale
        )
        let displayedChromeAxisLength = min(axisLength(of: displayedContentSize, position: position), availableAxisLength)
        layout.setChromeSize(displayedChromeSize(
            for: displayedContentSize,
            displayedAxisLength: displayedChromeAxisLength,
            position: position
        ))
        // Keep the chrome stretched across the current dock axis even when the
        // tile layout itself remains content-sized.
        let displayedAxisLength = availableAxisLength
        let width = displayedWindowWidth(
            for: displayedContentSize,
            displayedAxisLength: displayedAxisLength,
            availableAxisLength: availableAxisLength,
            contentPadding: contentPadding,
            position: position
        )
        let height = displayedWindowHeight(
            for: displayedContentSize,
            displayedAxisLength: displayedAxisLength,
            contentPadding: contentPadding,
            position: position
        )
        let size = CGSize(width: width, height: height)
        let origin = frameOrigin(
            in: screenBounds,
            size: size,
            position: position,
            visibilityState: visibilityState
        )

        let frame = CGRect(origin: origin, size: size)
        applyFrame(frame, animated: animated, duration: duration)
    }

    private func applyFrame(_ frame: CGRect, animated: Bool, duration: TimeInterval?) {
        let shouldAnimate = animated && hasResolvedInitialFrame

        guard shouldAnimate else {
            setFrame(frame, display: true, animate: false)
            revealAfterInitialFrameIfNeeded()
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration ?? autohideAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().setFrame(frame, display: true)
        }
    }

    private func revealAfterInitialFrameIfNeeded() {
        guard !hasResolvedInitialFrame else { return }
        hasResolvedInitialFrame = true
        alphaValue = 1
    }

    private var autohideAnimationDuration: TimeInterval {
        max(0.16, min(0.5, baseAutohideAnimationDuration * max(dockSettings.autohideTimeModifier, 0.01)))
    }

    private func overflowContentScale(
        for contentSize: CGSize,
        availableAxisLength: CGFloat,
        position: ResolvedDockWindowPosition
    ) -> CGFloat {
        guard preferences.overflowBehavior == .rescale, availableAxisLength > 0 else {
            return 1
        }

        let contentAxisLength = axisLength(of: contentSize, position: position)
        guard contentAxisLength > 0 else { return 1 }
        return min(1, availableAxisLength / contentAxisLength)
    }

    private func shouldCompactWidgetsForOverflow(
        contentSize: CGSize,
        availableAxisLength: CGFloat,
        position: ResolvedDockWindowPosition
    ) -> Bool {
        guard preferences.overflowBehavior == .rescale, availableAxisLength > 0 else {
            return false
        }

        return axisLength(of: contentSize, position: position) > availableAxisLength
    }

    private func axisLength(of size: CGSize, position: ResolvedDockWindowPosition) -> CGFloat {
        position.isVertical ? size.height : size.width
    }

    private func shouldReserveStatusBarLength(
        for contentSize: CGSize,
        availableAxisLength: CGFloat,
        position: ResolvedDockWindowPosition
    ) -> Bool {
        axisLength(of: contentSize, position: position) > availableAxisLength
    }

    private var reservedStatusBarLength: CGFloat {
        NSStatusBar.system.thickness * 4
    }

    private func displayedWindowWidth(
        for contentSize: CGSize,
        displayedAxisLength: CGFloat,
        availableAxisLength: CGFloat,
        contentPadding: CGFloat,
        position: ResolvedDockWindowPosition
    ) -> CGFloat {
        if position.isVertical {
            return contentSize.width + contentPadding * 2
        }

        let visibleAxisLength = availableAxisLength > 0
            ? min(max(minimumWidth, displayedAxisLength), availableAxisLength)
            : max(minimumWidth, displayedAxisLength)
        return visibleAxisLength + contentPadding * 2
    }

    private func displayedWindowHeight(
        for contentSize: CGSize,
        displayedAxisLength: CGFloat,
        contentPadding: CGFloat,
        position: ResolvedDockWindowPosition
    ) -> CGFloat {
        if position.isVertical {
            return displayedAxisLength + contentPadding * 2
        }

        return contentSize.height + contentPadding * 2
    }

    private func displayedChromeSize(
        for contentSize: CGSize,
        displayedAxisLength: CGFloat,
        position: ResolvedDockWindowPosition
    ) -> CGSize {
        if position.isVertical {
            return CGSize(width: contentSize.width, height: displayedAxisLength)
        }

        return CGSize(width: displayedAxisLength, height: contentSize.height)
    }

    private func frameOrigin(
        in screenBounds: CGRect,
        size: CGSize,
        position: ResolvedDockWindowPosition,
        visibilityState: VisibilityState
    ) -> CGPoint {
        let hidden = visibilityState == .hidden

        switch position {
        case .top:
            return CGPoint(
                x: screenBounds.minX + (screenBounds.width - size.width) / 2,
                y: hidden ? screenBounds.maxY - hiddenRevealThickness : screenBounds.maxY - size.height
            )
        case .left:
            return CGPoint(
                x: hidden ? screenBounds.minX - size.width + hiddenRevealThickness : screenBounds.minX,
                y: screenBounds.minY + (screenBounds.height - size.height) / 2
            )
        case .right:
            return CGPoint(
                x: hidden ? screenBounds.maxX - hiddenRevealThickness : screenBounds.maxX - size.width,
                y: screenBounds.minY + (screenBounds.height - size.height) / 2
            )
        case .bottom:
            return CGPoint(
                x: screenBounds.minX + (screenBounds.width - size.width) / 2,
                y: hidden ? screenBounds.minY - size.height + hiddenRevealThickness : screenBounds.minY
            )
        }
    }

    private func targetScreen() -> NSScreen? {
        switch preferences.windowDisplayTarget {
        case .primaryDisplay:
            return NSScreen.screens.first ?? NSScreen.main
        case .displayContainingPointer:
            let mouseLocation = NSEvent.mouseLocation
            return NSScreen.screens.first { $0.frame.contains(mouseLocation) }
                ?? screen
                ?? NSScreen.main
                ?? NSScreen.screens.first
        }
    }

    private func updateFullscreenStateAndApply(animated: Bool) {
        let newValue = computeFullscreenStateOnTargetScreen()
        guard newValue != isFullscreenActiveOnTargetScreen else { return }
        isFullscreenActiveOnTargetScreen = newValue
        applyEffectiveVisibility(animated: animated)
    }

    private func scheduleFullscreenRecheck() {
        fullscreenRecheckWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.updateFullscreenStateAndApply(animated: true)
        }
        fullscreenRecheckWorkItem = workItem
        // Long enough to cover the macOS fullscreen exit animation, which can
        // run up to ~750 ms with reduce-motion off.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85, execute: workItem)
    }

    private func computeFullscreenStateOnTargetScreen() -> Bool {
        guard let targetFrame = targetScreen()?.frame,
              let primaryScreenHeight = NSScreen.screens.first?.frame.height
        else {
            return false
        }

        let listOptions: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(listOptions, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier

        for info in windows {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }

            if let pidNumber = info[kCGWindowOwnerPID as String] as? NSNumber,
               pidNumber.int32Value == ownPID {
                continue
            }

            guard let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let cgBounds = CGRect(dictionaryRepresentation: boundsDict)
            else { continue }

            // CGWindow uses a flipped Y axis with origin at the top-left of the
            // primary display; convert back to NSScreen space before comparing.
            let nsBounds = CGRect(
                x: cgBounds.minX,
                y: primaryScreenHeight - cgBounds.maxY,
                width: cgBounds.width,
                height: cgBounds.height
            )

            // A genuine fullscreen window covers the entire NSScreen.frame
            // (including the menubar area). Maximized windows only cover
            // visibleFrame, so this distinguishes the two.
            if abs(nsBounds.minX - targetFrame.minX) < 1,
               abs(nsBounds.minY - targetFrame.minY) < 1,
               abs(nsBounds.width - targetFrame.width) < 1,
               abs(nsBounds.height - targetFrame.height) < 1 {
                return true
            }
        }

        return false
    }
}
