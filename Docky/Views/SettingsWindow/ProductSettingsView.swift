//
//  ProductSettingsView.swift
//  Docky
//

import SwiftUI

struct ProductSettingsView: View {
    @ObservedObject private var product = ProductService.shared
    @ObservedObject private var appUpdateService = AppUpdateService.shared
    @State private var licenseKey: String = ""

    private let updateIntervals: [TimeInterval] = [3600, 86_400, 604_800, 2_629_800]

    var body: some View {
        Form {
            Section("Updates") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Button("Check for Updates…") {
                            appUpdateService.checkForUpdates()
                        }
                        .disabled(!appUpdateService.canCheckForUpdates)

                        Spacer()
                    }

                    Toggle("Automatically Check for Updates", isOn: $appUpdateService.automaticallyChecksForUpdates)
                        .font(.headline)

                    Toggle("Automatically Download Updates", isOn: $appUpdateService.automaticallyDownloadsUpdates)
                        .font(.headline)
                        .disabled(!appUpdateService.automaticallyChecksForUpdates)

                    HStack {
                        Text("Check Interval")
                            .font(.headline)

                        Spacer()

                        Picker("Check Interval", selection: $appUpdateService.updateCheckInterval) {
                            ForEach(updateIntervals, id: \.self) { interval in
                                Text(title(for: interval)).tag(interval)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .disabled(!appUpdateService.automaticallyChecksForUpdates)
                    }

                    Text("Docky can periodically check docky.quintero.gt for new signed releases. Sparkle stores these update preferences directly in your user defaults.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }

            Section("Current Plan") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Tier")
                            .font(.headline)

                        Spacer()

                        Text(product.currentTier.title)
                            .foregroundStyle(.secondary)
                    }

                    HStack(alignment: .top) {
                        Text(product.registrationStatus.title)
                            .font(.headline)

                        Spacer()

                        if product.currentTier == .pro {
                            ProBadge()
                        }
                    }

                    Text(product.registrationStatus.message)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }

            Section("Register Product") {
                VStack(alignment: .leading, spacing: 12) {
                    SecureField(product.hasStoredLicenseKey ? "Replace License Key" : "License Key", text: $licenseKey)
                        .textFieldStyle(.roundedBorder)
                        .disabled(product.isVerifyingRegistration)

                    Text("License keys are verified with Gumroad and then stored locally on this Mac. Each license can be activated on up to \(ProductService.maximumActivationCount) Macs.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if product.isVerifyingRegistration {
                        ProgressView("Verifying License...")
                    }

                    HStack(spacing: 10) {
                        Button("Verify License") {
                            product.registerProduct(licenseKey: licenseKey)
                            licenseKey = ""
                        }
                        .disabled(licenseKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || product.isVerifyingRegistration)

                        Button("Clear Registration") {
                            product.clearRegistration()
                            syncFieldsFromService()
                        }
                        .disabled((!product.hasStoredLicenseKey && product.currentTier == .free) || product.isVerifyingRegistration)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Docky Pro Features") {
                ForEach(ProductFeature.productSettingsFeatures) { feature in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(feature.title)
                                .font(.headline)
                            Spacer()
                            ProBadge()
                        }

                        Text(feature.summary)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 20)
        .onAppear(perform: syncFieldsFromService)
    }

    private func syncFieldsFromService() {
        licenseKey = ""
    }

    private func title(for interval: TimeInterval) -> String {
        switch interval {
        case 3600:
            "Hourly"
        case 86_400:
            "Daily"
        case 604_800:
            "Weekly"
        case 2_629_800:
            "Monthly"
        default:
            "Custom"
        }
    }
}
