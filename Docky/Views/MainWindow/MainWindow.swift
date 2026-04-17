//
//  MainWindow.swift
//  Docky
//
//  Created by Jose Quintero on 17/04/26.
//

import AppKit
import Combine

final class MainWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override var level: NSWindow.Level { get { .mainMenu } set {} }

    private let backgroundBlurRadius = 10
    private let dockSettings = DockSettingsService.shared
    private let preferences = DockyPreferences.shared
    private let tileStore = TileStore.shared
    private let minimumWidth: CGFloat = 120
    private var cancellables: Set<AnyCancellable> = []

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        backgroundColor = .clear
        isOpaque = false
        isMovableByWindowBackground = true
        observeFrameInputs()
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
        let signals: [AnyPublisher<Void, Never>] = [
            dockSettings.$tileSize.map { _ in () }.eraseToAnyPublisher(),
            dockSettings.$largeSize.map { _ in () }.eraseToAnyPublisher(),
            dockSettings.$magnification.map { _ in () }.eraseToAnyPublisher(),
            preferences.$tileVerticalPadding.map { _ in () }.eraseToAnyPublisher(),
            preferences.$tileSpacing.map { _ in () }.eraseToAnyPublisher(),
            tileStore.$tiles.map { _ in () }.eraseToAnyPublisher(),
        ]
        Publishers.MergeMany(signals)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyFrame() }
            .store(in: &cancellables)
    }

    private func applyFrame() {
        let screenBounds = NSScreen.main?.frame ?? .zero
        let iconHeight = dockSettings.magnification ? dockSettings.largeSize : dockSettings.tileSize
        let height = iconHeight + preferences.tileVerticalPadding * 2

        let contentWidth = TileContainerView.contentWidth(
            tiles: tileStore.tiles,
            tileSize: dockSettings.tileSize,
            tileSpacing: preferences.tileSpacing
        )
        let width = max(minimumWidth, contentWidth)

        setFrame(
            CGRect(
                x: (screenBounds.width - width) / 2,
                y: 0,
                width: width,
                height: height
            ),
            display: true,
            animate: false
        )
    }
}
