//
//  IconCacheService.swift
//  Docky
//
//  In-memory cache for icons surfaced in tiles. Wraps NSCache so eviction
//  under memory pressure is handled by the OS. `NSWorkspace.icon(forFile:)`
//  itself is fast but SwiftUI re-reads the icon every view update — caching
//  avoids repeated LaunchServices hops and redundant NSImage wrapping.
//

import AppKit

final class IconCacheService {
    static let shared = IconCacheService()

    private let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 256
        return cache
    }()

    private init() {}

    func icon(forBundleIdentifier bundleIdentifier: String) -> NSImage {
        let key = "bundle:\(bundleIdentifier)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let image = loadIcon(forBundleIdentifier: bundleIdentifier)
        cache.setObject(image, forKey: key)
        return image
    }

    func icon(forFileURL url: URL) -> NSImage {
        let key = "path:\(url.path)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        cache.setObject(image, forKey: key)
        return image
    }

    func invalidate() {
        cache.removeAllObjects()
    }

    private func loadIcon(forBundleIdentifier bundleIdentifier: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil) ?? NSImage()
    }
}
