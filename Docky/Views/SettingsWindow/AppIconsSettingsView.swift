//
//  AppIconsSettingsView.swift
//  Docky
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AppIconsSettingsView: View {
    @ObservedObject private var preferences = DockyPreferences.shared
    @ObservedObject private var workspace = WorkspaceService.shared

    var body: some View {
        Form {
            Section("Overrides") {
                Text("Choose a custom image for any app Docky currently knows about. Custom app icons follow Docky's circle tile clipping when circle tiles are enabled.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if appEntries.isEmpty {
                    Text("No apps are currently available for icon overrides.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appEntries) { entry in
                        AppIconOverrideRow(entry: entry)
                            .padding(.vertical, 4)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 20)
    }

    private var appEntries: [AppIconSettingsEntry] {
        var bundleIdentifiers: Set<String> = ["com.apple.finder"]
        bundleIdentifiers.formUnion(workspace.runningApps.map(\.bundleIdentifier))
        bundleIdentifiers.formUnion(preferences.appIconOverrides.map(\.bundleIdentifier))
        bundleIdentifiers.formUnion(preferences.widgetPlacements.map(\.ownerBundleIdentifier))

        for item in preferences.pinnedItems {
            if let bundleIdentifier = item.bundleIdentifier {
                bundleIdentifiers.insert(bundleIdentifier)
            }

            bundleIdentifiers.formUnion(item.folderBundleIdentifiers)
        }

        return bundleIdentifiers.compactMap { bundleIdentifier in
            let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
            let displayName = appURL.map { FileManager.default.displayName(atPath: $0.path) } ?? bundleIdentifier
            let subtitle = appURL == nil
                ? "\(bundleIdentifier) • App not currently found on disk"
                : bundleIdentifier

            return AppIconSettingsEntry(
                bundleIdentifier: bundleIdentifier,
                displayName: displayName,
                subtitle: subtitle,
                systemIcon: IconCacheService.shared.icon(forBundleIdentifier: bundleIdentifier)
            )
        }
        .sorted { lhs, rhs in
            let comparison = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
            if comparison == .orderedSame {
                return lhs.bundleIdentifier.localizedCaseInsensitiveCompare(rhs.bundleIdentifier) == .orderedAscending
            }
            return comparison == .orderedAscending
        }
    }
}

private struct AppIconOverrideRow: View {
    let entry: AppIconSettingsEntry

    @ObservedObject private var preferences = DockyPreferences.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Image(nsImage: previewImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.displayName)
                        .font(.headline)

                    Text(entry.subtitle)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .textSelection(.enabled)

                    if let overrideName {
                        Text("Override: \(overrideName)")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    Button("Choose Image...") {
                        chooseOverrideImage()
                    }

                    if overrideEntry != nil {
                        Button("Clear") {
                            preferences.removeAppIconOverride(bundleIdentifier: entry.bundleIdentifier)
                        }
                    }
                }
            }

        }
    }

    private var overrideEntry: AppIconOverride? {
        preferences.appIconOverride(forBundleIdentifier: entry.bundleIdentifier)
    }

    private var overrideName: String? {
        guard let iconPath = overrideEntry?.iconPath, !iconPath.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: iconPath).lastPathComponent
    }

    private var previewImage: NSImage {
        if let overrideURL = overrideEntry?.effectiveIconURL,
           let overrideImage = IconCacheService.shared.image(forImageFileURL: overrideURL) {
            return overrideImage
        }

        return entry.systemIcon
    }

    private func chooseOverrideImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK, let url = panel.url {
            preferences.setAppIconOverride(
                bundleIdentifier: entry.bundleIdentifier,
                iconPath: url.path
            )
        }
    }
}

private struct AppIconSettingsEntry: Identifiable {
    let bundleIdentifier: String
    let displayName: String
    let subtitle: String
    let systemIcon: NSImage

    var id: String { bundleIdentifier }
}
