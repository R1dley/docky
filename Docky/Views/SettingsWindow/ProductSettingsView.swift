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
        }
        .formStyle(.grouped)
        .padding(.horizontal, 20)
        .onAppear(perform: syncFieldsFromService)
        .onChange(of: product.trialExpiresAt) { _, expiresAt in
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
                    .textContentType(.emailAddress)
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
