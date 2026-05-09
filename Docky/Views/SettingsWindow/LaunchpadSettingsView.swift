//
//  LaunchpadSettingsView.swift
//  Docky
//

import SwiftUI

struct LaunchpadSettingsView: View {
    @Bindable private var preferences = DockyPreferences.shared
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

                        Stepper("\(preferences.launchpadGridColumnCount)", value: $preferences.launchpadGridColumnCount, in: 1...12)
                            .foregroundStyle(.secondary)
                            .disabled(!product.isUnlocked(.launchpad) || !preferences.enablesLaunchpadOverlay)
                    }

                    HStack {
                        Text("Grid Rows")
                            .font(.headline)

                        Spacer()

                        Stepper("\(preferences.launchpadGridRowCount)", value: $preferences.launchpadGridRowCount, in: 1...10)
                            .foregroundStyle(.secondary)
                            .disabled(!product.isUnlocked(.launchpad) || !preferences.enablesLaunchpadOverlay)
                    }

                    Text("Sets the Launchpad grid dimensions. Docky uses these counts when the icons fit on screen, defaulting to 7 columns × 5 rows.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }

            Section("Appearance") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Transparency")
                            .font(.headline)

                        Spacer()

                        Text("\(Int(preferences.launchpadOverlayTransparency * 100))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Slider(value: launchpadTransparencyBinding, in: 0...1, step: 0.01)
                        .disabled(!product.isUnlocked(.launchpad) || !preferences.enablesLaunchpadOverlay)

                    Text("Adjusts how transparent the Launchpad backdrop is. Lower values darken the screen behind the grid; higher values let more of your desktop show through.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
    }

    private var launchpadTransparencyBinding: Binding<CGFloat> {
        Binding(
            get: { preferences.launchpadOverlayTransparency },
            set: { preferences.launchpadOverlayTransparency = min(max($0, 0), 1) }
        )
    }
}
