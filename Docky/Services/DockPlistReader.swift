//
//  DockPlistReader.swift
//  Docky
//
//  Shared read path for the com.apple.dock plist. Stateless helper used by
//  DockSettingsService and TileStore so the two-path (bookmarked URL vs
//  CFPreferences) logic lives in exactly one place.
//
//  Sandbox behavior: returns nil when neither path is available, letting
//  callers gracefully no-op per the project's sandbox-fallback rule.
//

import Foundation

enum DockPlistReader {
    private static let domain = "com.apple.dock" as CFString

    /// Full dock plist as a dictionary. Nil when no access path is available.
    static func read() -> [String: Any]? {
        if let dict = readFromBookmark() {
            return dict
        }
        if !AppEnvironment.isSandboxed, let dict = readFromCFPreferences() {
            return dict
        }
        return nil
    }

    private static func readFromBookmark() -> [String: Any]? {
        PermissionsService.shared.withDockPlistURL { url -> [String: Any]? in
            guard let url else { return nil }
            guard let data = try? Data(contentsOf: url) else { return nil }
            return (try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            )) as? [String: Any]
        }
    }

    private static func readFromCFPreferences() -> [String: Any]? {
        CFPreferencesAppSynchronize(domain)
        let keys: [String] = [
            "orientation", "tilesize", "largesize", "magnification",
            "autohide", "autohide-delay", "autohide-time-modifier",
            "mineffect", "minimize-to-application",
            "show-recents", "show-process-indicators",
            "persistent-apps", "persistent-others"
        ]
        var out: [String: Any] = [:]
        for key in keys {
            if let value = CFPreferencesCopyAppValue(key as CFString, domain) {
                out[key] = value
            }
        }
        return out.isEmpty ? nil : out
    }
}
