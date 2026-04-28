//
//  WindowManagementSettingsView.swift
//  Docky
//

import SwiftUI

struct WindowManagementSettingsView: View {
    @ObservedObject private var preferences = DockyPreferences.shared
    @ObservedObject private var product = ProductService.shared
    @State private var isRecordingShortcut = false

    var body: some View {
        Form {
            Section("Window Switcher") {
                if !product.isUnlocked(.windowSwitcher) {
                    ProFeatureNotice(feature: .windowSwitcher)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Enable Window Switcher", isOn: $preferences.enablesWindowSwitcher)
                        .font(.headline)
                        .disabled(!product.isUnlocked(.windowSwitcher))

                    Text("Turn Docky's Cmd-Tab-style switcher on or off without clearing its shortcut or preview preference.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Shortcut")
                                .font(.headline)

                            Text("Choose the global shortcut that opens Docky's Cmd-Tab-style window switcher.")
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        ShortcutRecorderControl(
                            shortcut: preferences.windowSwitcherShortcut,
                            isRecording: $isRecordingShortcut,
                            resetShortcut: KeyboardShortcut(keyCode: 48, modifierFlags: [.option])
                        ) { shortcut in
                            preferences.windowSwitcherShortcut = shortcut
                        }
                        .disabled(!product.isUnlocked(.windowSwitcher) || !preferences.enablesWindowSwitcher)
                    }

                    Text("While the switcher is open, keep the shortcut modifiers held and tap the shortcut again to cycle. Release the modifiers to focus the selected window.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Preview Selected Window In Place", isOn: $preferences.showsWindowSwitcherFocusPreview)
                        .font(.headline)
                        .disabled(!product.isUnlocked(.windowSwitcher) || !preferences.enablesWindowSwitcher)

                    Text("After the current switcher selection stays put for a moment, darken the backdrop and draw that window at its on-screen position behind the switcher.")
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
