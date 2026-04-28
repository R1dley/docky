//
//  ActionCatalogSettingsView.swift
//  Docky
//

import SwiftUI

struct ActionCatalogSettingsView: View {
    @ObservedObject private var catalog = MenuCatalogService.shared
    @ObservedObject private var product = ProductService.shared

    var body: some View {
        Form {
            if !product.isUnlocked(.scriptedActions) {
                Section {
                    ProFeatureNotice(feature: .scriptedActions)
                }
            }

            Section("Catalog Packages") {
                if catalog.packageSummaries.isEmpty {
                    Text("No catalog packages loaded.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(catalog.packageSummaries) { package in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(package.title)
                                    .font(.headline)
                                Spacer()
                                Text(package.version)
                                    .foregroundStyle(.secondary)
                            }

                            Text("by \(package.author) • \(package.actionCount) actions • \(package.reviewStatus)")
                                .foregroundStyle(.secondary)

                            if let description = package.description {
                                Text(description)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section("Scripted Actions") {
                Text("Docky loads menu definitions from bundled JSON and executes only reviewed action kinds: builtin, applescript, and menuClick. App-targeted AppleScript and menuClick actions may trigger macOS Automation prompts the first time you use them. The catalog format is designed so future curated packages can add actions and append menu items at approved insertion points without replacing Docky’s core menus.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Text("Catalog Refresh")
                        .font(.headline)

                    Spacer()

                    Button("Reload Catalog") {
                        catalog.reload()
                    }
                    .disabled(!product.isUnlocked(.scriptedActions))
                }
            }

            if !catalog.diagnostics.isEmpty {
                Section("Diagnostics") {
                    ForEach(Array(catalog.diagnostics.enumerated()), id: \.offset) { item in
                        Text(item.element)
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 20)
    }
}
