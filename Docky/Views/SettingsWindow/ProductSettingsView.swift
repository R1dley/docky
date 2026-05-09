//
//  ProductSettingsView.swift
//  Docky
//

import SwiftUI

struct ProductSettingsView: View {
    @ObservedObject private var product = ProductService.shared
    @State private var licenseKey: String = ""
    @State private var trialEmail: String = ""
    @State private var isShowingTrialSheet = false
    @State private var isShowingResetConfirmation = false

    var body: some View {
        Form {
            Section("Current Plan") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Tier")
                            .font(.headline)

                        Spacer()

                        

                        if product.currentTier == .pro {
                            ProBadge()
                        } else {
                            Text(product.currentTier.title)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(alignment: .top) {
                        Text(product.registrationStatus.title)
                            .font(.headline)
                        
                        Spacer()
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
                        Button("Start Trial") {
                            trialEmail = product.trialEmail
                            isShowingTrialSheet = true
                        }
                        .disabled(product.currentTier == .pro || product.isVerifyingRegistration || product.isStartingTrial)

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

            Section("Reset Preferences") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Restores all of Docky's appearance, behavior, widget, and window-management preferences to their default values. Your pinned dock items and Pro registration are unaffected.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("Reset to Defaults", role: .destructive) {
                        isShowingResetConfirmation = true
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Reset all Docky preferences?",
            isPresented: $isShowingResetConfirmation
        ) {
            Button("Reset to Defaults", role: .destructive) {
                DockyPreferences.shared.resetToDefaults()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All appearance, behavior, widget, and window-management settings will return to their defaults. This cannot be undone.")
        }
        .onAppear(perform: syncFieldsFromService)
        .onChange(of: product.trialExpiresAt) { expiresAt in
            guard expiresAt != nil, product.currentTier == .pro else {
                return
            }

            isShowingTrialSheet = false
        }
        .sheet(isPresented: $isShowingTrialSheet) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Start Your Trial")
                    .font(.title2.weight(.semibold))

                Text("Enter your email address to start a Docky Pro trial. Trial eligibility is checked online and can only be used once per email.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                TextField("Email Address", text: $trialEmail)
                    .textFieldStyle(.roundedBorder)
                    .modifier(EmailAddressContentTypeIfAvailable())
                    .disabled(product.isStartingTrial)

                if product.isStartingTrial {
                    HStack {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Starting Trial...")
                            .font(.body)
                    }
                }

                Text(product.registrationStatus.message)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Spacer()

                    Button("Cancel") {
                        isShowingTrialSheet = false
                    }
                    .keyboardShortcut(.cancelAction)
                    .disabled(product.isStartingTrial)

                    Button("Start Trial") {
                        product.startTrial(email: trialEmail)
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        trialEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        product.currentTier == .pro ||
                        product.isStartingTrial ||
                        product.isVerifyingRegistration
                    )
                }
            }
            .padding(20)
            .frame(width: 420)
        }
    }

    private func syncFieldsFromService() {
        licenseKey = ""
        trialEmail = product.trialEmail
    }
}

/// `UITextContentType.emailAddress` on macOS is gated behind 14+; on 13
/// — or when the autofill content-type feature is force-disabled via
/// `FeatureGate` — the text field works without the autofill hint.
private struct EmailAddressContentTypeIfAvailable: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if FeatureGate.shared.isAvailable(.emailAutofillContentType), #available(macOS 14.0, *) {
            content.textContentType(.emailAddress)
        } else {
            content
        }
    }
}
