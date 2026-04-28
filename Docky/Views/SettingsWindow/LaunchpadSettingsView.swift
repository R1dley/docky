//
//  LaunchpadSettingsView.swift
//  Docky
//

import SwiftUI

struct LaunchpadSettingsView: View {
    @ObservedObject private var preferences = DockyPreferences.shared
    @ObservedObject private var product = ProductService.shared
    @State private var isRecordingShortcut = false

    var body: some View {
        Form {
            Section("Availability") {
                if !product.isUnlocked(.launchpad) {
                    ProFeatureNotice(feature: .launchpad)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Enable Launchpad", isOn: $preferences.enablesLaunchpadOverlay)
                        .font(.headline)
                        .disabled(!product.isUnlocked(.launchpad))

                    Text("Turn Docky's Launchpad overlay on or off without removing its shortcut or layout preferences.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }

            Section("Shortcut") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Global Shortcut")
                                .font(.headline)

                            Text("Optionally assign a global shortcut that toggles Docky's Launchpad overlay from anywhere.")
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        ShortcutRecorderControl(
                            shortcut: preferences.launchpadShortcut,
                            isRecording: $isRecordingShortcut,
                            resetShortcut: nil
                        ) { shortcut in
                            preferences.launchpadShortcut = shortcut
                        }
                        .disabled(!product.isUnlocked(.launchpad) || !preferences.enablesLaunchpadOverlay)
                    }

                    Text("Leave this unset if you only want to open Launchpad from the Docky tile or context menu.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }

            Section("Layout") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Grid Columns")
                            .font(.headline)

                        Spacer()

                        Stepper("\(preferences.launchpadGridColumnCount)", value: $preferences.launchpadGridColumnCount, in: 1...10)
                            .foregroundStyle(.secondary)
                            .disabled(!product.isUnlocked(.launchpad) || !preferences.enablesLaunchpadOverlay)
                    }

                    Text("Controls the default Launchpad grid width. Docky uses this many columns when they fit on screen, starting at 7 by default.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 20)
    }
}
