//
//  PermissionsService.swift
//  Docky
//
//  Tracks access Docky needs:
//    - .dockSettings  → com.apple.dock.plist (as a file)
//    - .userFolders   → home directory (covers Downloads/Documents/etc.)
//
//  Each grants through one of two paths:
//    - Full Disk Access (FDA) — unsandboxed only. Probed via an attempted
//      read of a TCC-protected directory (inket/FullDiskAccess approach).
//    - User-selected file/folder — NSOpenPanel → security-scoped bookmark.
//
//  Bookmarks use `.withSecurityScope` only when sandboxed; plain bookmarks
//  otherwise. Callers should read through `withDockPlistURL` /
//  `withUserFoldersAccess` so scope start/stop is handled centrally.
//

import AppKit
import Combine
import Darwin
import UniformTypeIdentifiers

enum PermissionStatus {
    case granted
    case denied
    case notDetermined
}

enum GrantMethod {
    case fullDiskAccess
    case userSelectedFile
    case automation
}

enum Permission: String, CaseIterable, Identifiable {
    case dockSettings
    case userFolders
    case finderAutomation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dockSettings: return "Dock Settings Access"
        case .userFolders: return "User Folders Access"
        case .finderAutomation: return "Finder Automation"
        }
    }

    var explanation: String {
        switch self {
        case .dockSettings:
            return "Docky reads your system Dock configuration (icon size, magnification, position, auto-hide) so its appearance matches the native Dock. No data leaves your Mac."
        case .userFolders:
            return "Docky reads the contents of folders pinned to the dock so it can preview the most recent items (Downloads, Documents, etc.). Grant access to your home folder once — everything inside will be available. No data leaves your Mac."
        case .finderAutomation:
            return "Docky can ask Finder to reveal files, open folders in Finder, open the Trash, and empty the Trash. macOS controls this separately from file access, and you can grant or revoke it at any time in Privacy & Security."
        }
    }

    var systemSettingsURL: URL? {
        switch self {
        case .dockSettings, .userFolders:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
        case .finderAutomation:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
        }
    }

    var isRequiredAtLaunch: Bool {
        switch self {
        case .dockSettings, .userFolders:
            return true
        case .finderAutomation:
            return false
        }
    }
}

final class PermissionsService: ObservableObject {
    static let shared = PermissionsService()

    @Published private(set) var dockSettings: PermissionStatus = .notDetermined
    @Published private(set) var dockSettingsGrantMethod: GrantMethod?
    @Published private(set) var dockPlistURL: URL?

    @Published private(set) var userFolders: PermissionStatus = .notDetermined
    @Published private(set) var userFoldersGrantMethod: GrantMethod?
    @Published private(set) var userFoldersURL: URL?

    @Published private(set) var finderAutomation: PermissionStatus = .notDetermined
    @Published private(set) var finderAutomationGrantMethod: GrantMethod?

    private let dockBookmarkKey = "docky.dockPlistBookmark"
    private let userFoldersBookmarkKey = "docky.userFoldersBookmark"
    private let finderAutomationStatusKey = "docky.finderAutomationStatus"
    private let dockPlistFilename = "com.apple.dock.plist"

    private init() {
        refresh()
    }

    // MARK: - Status

    func status(for permission: Permission) -> PermissionStatus {
        switch permission {
        case .dockSettings: return dockSettings
        case .userFolders: return userFolders
        case .finderAutomation: return finderAutomation
        }
    }

    var missingPermissions: [Permission] {
        Permission.allCases.filter { status(for: $0) != .granted }
    }

    var missingRequiredPermissions: [Permission] {
        Permission.allCases.filter { $0.isRequiredAtLaunch && status(for: $0) != .granted }
    }

    var setupPermissions: [Permission] {
        Permission.allCases.filter {
            if $0.isRequiredAtLaunch {
                return status(for: $0) != .granted
            }
            return status(for: $0) == .notDetermined
        }
    }

    var allGranted: Bool { missingPermissions.isEmpty }

    var allRequiredGranted: Bool { missingRequiredPermissions.isEmpty }

    var setupComplete: Bool { setupPermissions.isEmpty }

    func refresh() {
        let fdaGranted = checkFullDiskAccess()
        refreshDockSettings(fdaGranted: fdaGranted)
        refreshUserFolders(fdaGranted: fdaGranted)
        refreshFinderAutomation()
    }

    // MARK: - Grant actions

    func openSystemSettings(for permission: Permission) {
        guard let url = permission.systemSettingsURL else { return }
        NSWorkspace.shared.open(url)
    }

    @discardableResult
    func requestUserSelectedFile(for permission: Permission) -> Bool {
        switch permission {
        case .dockSettings:
            return presentDockPlistPicker()
        case .userFolders:
            return presentUserFoldersPicker()
        case .finderAutomation:
            return false
        }
    }

    func requestAutomationPermission(for permission: Permission) async -> Bool {
        switch permission {
        case .finderAutomation:
            return await AppleScriptService.shared.requestFinderAutomationPermission()
        case .dockSettings, .userFolders:
            return false
        }
    }

    func revokeUserSelectedFile(for permission: Permission) {
        switch permission {
        case .dockSettings:
            UserDefaults.standard.removeObject(forKey: dockBookmarkKey)
        case .userFolders:
            UserDefaults.standard.removeObject(forKey: userFoldersBookmarkKey)
        case .finderAutomation:
            return
        }
        refresh()
    }

    func clearAutomationStatus(for permission: Permission) {
        guard permission == .finderAutomation else { return }
        UserDefaults.standard.removeObject(forKey: finderAutomationStatusKey)
        refreshFinderAutomation()
    }

    // MARK: - Scoped access helpers

    /// Runs `body` with a usable dock plist URL, handling sandbox security
    /// scope. Passes nil when access isn't available.
    func withDockPlistURL<T>(_ body: (URL?) -> T) -> T {
        guard let url = dockPlistURL else { return body(nil) }
        return withSecurityScope(url: url, body: body)
    }

    /// Wraps arbitrary file-system work in the user-folders security scope
    /// (sandbox + bookmark) or runs directly (FDA / unsandboxed / denied).
    /// Body must be self-contained; the scope is torn down on return.
    func withUserFoldersAccess<T>(_ body: () -> T) -> T {
        guard userFoldersGrantMethod == .userSelectedFile, let url = userFoldersURL else {
            return body()
        }
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        return body()
    }

    // MARK: - Dock plist permission

    private func refreshDockSettings(fdaGranted: Bool) {
        if let url = resolveBookmark(
            key: dockBookmarkKey,
            expectedFilename: dockPlistFilename
        ) {
            dockPlistURL = url
            dockSettingsGrantMethod = .userSelectedFile
            dockSettings = .granted
            return
        }
        if fdaGranted {
            dockPlistURL = nil
            dockSettingsGrantMethod = .fullDiskAccess
            dockSettings = .granted
            return
        }
        dockPlistURL = nil
        dockSettingsGrantMethod = nil
        dockSettings = .denied
    }

    private func presentDockPlistPicker() -> Bool {
        let panel = NSOpenPanel()
        panel.title = "Select \(dockPlistFilename)"
        panel.message = "Choose \(dockPlistFilename) in your Preferences folder to grant Docky read access."
        panel.prompt = "Grant Access"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.treatsFilePackagesAsDirectories = true
        panel.allowedContentTypes = [UTType(filenameExtension: "plist") ?? .propertyList]
        panel.directoryURL = URL(fileURLWithPath: expandedPath("~/Library/Preferences"))
        panel.nameFieldStringValue = dockPlistFilename

        guard panel.runModal() == .OK, let url = panel.url else { return false }

        guard url.lastPathComponent == dockPlistFilename else {
            presentAlert(
                title: "Wrong file selected",
                body: "Docky expected \(dockPlistFilename) but got \(url.lastPathComponent). Please try again."
            )
            return false
        }

        guard storeBookmark(key: dockBookmarkKey, url: url) else {
            presentBookmarkError()
            return false
        }
        refresh()
        return dockSettings == .granted
    }

    // MARK: - User folders permission

    private func refreshUserFolders(fdaGranted: Bool) {
        if let url = resolveBookmark(key: userFoldersBookmarkKey, expectedFilename: nil) {
            userFoldersURL = url
            userFoldersGrantMethod = .userSelectedFile
            userFolders = .granted
            return
        }
        if fdaGranted {
            userFoldersURL = nil
            userFoldersGrantMethod = .fullDiskAccess
            userFolders = .granted
            return
        }
        userFoldersURL = nil
        userFoldersGrantMethod = nil
        userFolders = .denied
    }

    private func presentUserFoldersPicker() -> Bool {
        let panel = NSOpenPanel()
        panel.title = "Grant User Folders Access"
        panel.message = "Pick your home folder to grant Docky access to all folders inside it (Downloads, Documents, etc.)."
        panel.prompt = "Grant Access"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: expandedPath("~"))

        guard panel.runModal() == .OK, let url = panel.url else { return false }

        guard storeBookmark(key: userFoldersBookmarkKey, url: url) else {
            presentBookmarkError()
            return false
        }
        refresh()
        return userFolders == .granted
    }

    // MARK: - Finder automation permission

    func updateFinderAutomation(status: PermissionStatus) {
        switch status {
        case .granted:
            UserDefaults.standard.set("granted", forKey: finderAutomationStatusKey)
            finderAutomationGrantMethod = .automation
        case .denied:
            UserDefaults.standard.set("denied", forKey: finderAutomationStatusKey)
            finderAutomationGrantMethod = nil
        case .notDetermined:
            UserDefaults.standard.removeObject(forKey: finderAutomationStatusKey)
            finderAutomationGrantMethod = nil
        }
        finderAutomation = status
    }

    private func refreshFinderAutomation() {
        switch UserDefaults.standard.string(forKey: finderAutomationStatusKey) {
        case "granted":
            finderAutomation = .granted
            finderAutomationGrantMethod = .automation
        case "denied":
            finderAutomation = .denied
            finderAutomationGrantMethod = nil
        default:
            finderAutomation = .notDetermined
            finderAutomationGrantMethod = nil
        }
    }

    // MARK: - Bookmark storage

    private var bookmarkCreationOptions: URL.BookmarkCreationOptions {
        AppEnvironment.isSandboxed ? [.withSecurityScope] : []
    }

    private var bookmarkResolutionOptions: URL.BookmarkResolutionOptions {
        AppEnvironment.isSandboxed ? [.withSecurityScope] : []
    }

    private func storeBookmark(key: String, url: URL) -> Bool {
        do {
            let data = try url.bookmarkData(
                options: bookmarkCreationOptions,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(data, forKey: key)
            return true
        } catch {
            return false
        }
    }

    private func resolveBookmark(key: String, expectedFilename: String?) -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: bookmarkResolutionOptions,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if let expected = expectedFilename, url.lastPathComponent != expected {
                return nil
            }

            let readable: Bool
            if AppEnvironment.isSandboxed {
                let started = url.startAccessingSecurityScopedResource()
                defer { if started { url.stopAccessingSecurityScopedResource() } }
                readable = started && FileManager.default.isReadableFile(atPath: url.path)
            } else {
                readable = FileManager.default.isReadableFile(atPath: url.path)
            }
            guard readable else { return nil }

            if isStale { _ = refreshStaleBookmark(key: key, url: url) }
            return url
        } catch {
            return nil
        }
    }

    private func refreshStaleBookmark(key: String, url: URL) -> Bool {
        if AppEnvironment.isSandboxed {
            let started = url.startAccessingSecurityScopedResource()
            defer { if started { url.stopAccessingSecurityScopedResource() } }
            guard started else { return false }
            return storeBookmark(key: key, url: url)
        }
        return storeBookmark(key: key, url: url)
    }

    // MARK: - Full Disk Access probe

    private func checkFullDiskAccess() -> Bool {
        guard !AppEnvironment.isSandboxed else { return false }
        let probePath = expandedPath("~/Library/Containers/com.apple.stocks")
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: probePath)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Helpers

    private func withSecurityScope<T>(url: URL, body: (URL?) -> T) -> T {
        if AppEnvironment.isSandboxed {
            let started = url.startAccessingSecurityScopedResource()
            defer { if started { url.stopAccessingSecurityScopedResource() } }
            return body(started ? url : nil)
        }
        return body(url)
    }

    private func expandedPath(_ path: String) -> String {
        guard let pw = getpwuid(getuid()) else { return path }
        let homeURL = URL(
            fileURLWithFileSystemRepresentation: pw.pointee.pw_dir,
            isDirectory: true,
            relativeTo: nil
        )
        return path.replacingOccurrences(of: "~", with: homeURL.path)
    }

    private func presentAlert(title: String, body: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func presentBookmarkError() {
        presentAlert(
            title: "Couldn't save access",
            body: "Docky was unable to store a bookmark. Please try again or use Full Disk Access."
        )
    }
}
