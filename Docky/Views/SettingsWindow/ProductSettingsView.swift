//
//  ProductSettingsView.swift
//  Docky
//

import SwiftUI

struct ProductSettingsView: View {
    @ObservedObject private var product = ProductService.shared
    @State private var email: String = ""
    @State private var licenseKey: String = ""

    var body: some View {
        Form {
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
                    TextField("Email", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.emailAddress)

                    SecureField(product.hasStoredLicenseKey ? "Replace License Key" : "License Key", text: $licenseKey)
                        .textFieldStyle(.roundedBorder)

                    Text("License keys are stored locally on this Mac.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        Button("Save Registration") {
                            product.registerProduct(email: email, licenseKey: licenseKey)
                            licenseKey = ""
                        }
                        .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || licenseKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button("Clear Registration") {
                            product.clearRegistration()
                            syncFieldsFromService()
                        }
                        .disabled(product.registeredEmail.isEmpty && !product.hasStoredLicenseKey)
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
        email = product.registeredEmail
        licenseKey = ""
    }
}
