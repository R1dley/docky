//
//  FolderAccessService.swift
//  Docky
//
//  Reads folder contents for preview tiles. Relies on the .userFolders
//  permission granted via PermissionsService — either FDA (unsandboxed) or
//  a home-folder security-scoped bookmark (sandboxed). Silent no-op when
//  access isn't granted.
//

import Foundation

enum FolderContentsSnapshot: Equatable {
    case loaded([URL])
    case unreadable
}

final class FolderAccessService {
    static let shared = FolderAccessService()

    private let staleAfter: TimeInterval = 15
    private var contentsCache: [URL: (date: Date, items: [URL])] = [:]

    private init() {}

    /// All visible contents of the folder, newest-modified first.
    /// Cached briefly to avoid hitting the filesystem on every view update.
    func contents(of folderURL: URL) -> [URL] {
        if case .loaded(let items) = snapshot(of: folderURL) {
            return items
        }
        return []
    }

    func snapshot(of folderURL: URL) -> FolderContentsSnapshot {
        cachedSnapshot(of: folderURL)
    }

    /// Up to `limit` URLs from the folder, newest-modified first.
    func recentContents(of folderURL: URL, limit: Int = 3) -> [URL] {
        Array(contents(of: folderURL).prefix(limit))
    }

    private func cachedSnapshot(of folderURL: URL) -> FolderContentsSnapshot {
        if let cached = contentsCache[folderURL],
           Date().timeIntervalSince(cached.date) < staleAfter {
            return .loaded(cached.items)
        }

        let loaded: [URL]? = PermissionsService.shared.withUserFoldersAccess {
            guard FileManager.default.isReadableFile(atPath: folderURL.path) else {
                return nil
            }

            let keys: [URLResourceKey] = [.contentModificationDateKey]
            guard let items = try? FileManager.default.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            ) else { return nil }
            return items.sorted { Self.modDate($0) > Self.modDate($1) }
        }

        guard let loaded else {
            return .unreadable
        }

        contentsCache[folderURL] = (Date(), loaded)
        return .loaded(loaded)
    }

    func invalidateCache() {
        contentsCache.removeAll()
    }

    private static func modDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}
