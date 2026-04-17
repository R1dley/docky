//
//  AppEnvironment.swift
//  Docky
//
//  Process-level facts about the running Docky instance. Cache each query
//  since none of these can change within a process lifetime.
//

import Foundation

enum AppEnvironment {
    /// True when Docky is running inside the App Sandbox. Detected via the
    /// `APP_SANDBOX_CONTAINER_ID` environment variable the sandbox injects.
    /// Implications: no cross-app preference reads, no Full Disk Access,
    /// and file access requires user-selected-file + security-scoped bookmarks.
    static let isSandboxed: Bool = {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }()
}
