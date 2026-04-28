//
//  LaunchpadOverlayService.swift
//  Docky
//

import Combine
import Foundation

final class LaunchpadOverlayService: ObservableObject {
    static let shared = LaunchpadOverlayService()

    @Published private(set) var isPresented = false
    @Published private(set) var apps: [AppTile] = []

    private init() {}

    func toggle() {
        isPresented ? dismiss() : present()
    }

    func present() {
        guard ProductService.shared.isUnlocked(.launchpad), DockyPreferences.shared.enablesLaunchpadOverlay else {
            dismiss()
            return
        }

        apps = TileStore.shared.launchpadApps()
        isPresented = true
    }

    func dismiss() {
        isPresented = false
    }
}
