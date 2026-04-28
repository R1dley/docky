//
//  ProductService.swift
//  Docky
//

import Combine
import Foundation
import Security

enum ProductTier: String, Codable, CaseIterable, Identifiable {
    case free
    case pro

    var id: String { rawValue }

    var title: String {
        switch self {
        case .free:
            "Free"
        case .pro:
            "Pro"
        }
    }
}

enum ProductFeatureContext {
    case standard
    case newPlacement
    case existingPlacement
}

enum ProductAvailability: Equatable {
    case available
    case lockedExisting
    case unavailableForNewPlacement

    var isUnlocked: Bool {
        self == .available
    }

    var allowsNewPlacement: Bool {
        self == .available
    }
}

enum ProductFeature: Hashable, Identifiable {
    case launchpad
    case windowSwitcher
    case customAppIcons
    case groupedAppFolders
    case scriptedActions
    case smartStack
    case widget(WidgetKind)

    static let productSettingsFeatures: [ProductFeature] = [
        .launchpad,
        .windowSwitcher,
        .customAppIcons,
        .groupedAppFolders,
        .scriptedActions,
        .smartStack,
    ]

    var id: String {
        switch self {
        case .launchpad:
            "launchpad"
        case .windowSwitcher:
            "window-switcher"
        case .customAppIcons:
            "custom-app-icons"
        case .groupedAppFolders:
            "grouped-app-folders"
        case .scriptedActions:
            "scripted-actions"
        case .smartStack:
            "smart-stack"
        case .widget(let kind):
            "widget:\(kind.rawValue)"
        }
    }

    var title: String {
        switch self {
        case .launchpad:
            "Launchpad"
        case .windowSwitcher:
            "Window Switcher"
        case .customAppIcons:
            "Custom App Icons"
        case .groupedAppFolders:
            "Grouped App Folders"
        case .scriptedActions:
            "Scripted Actions"
        case .smartStack:
            "Smart Stack"
        case .widget(let kind):
            "\(kind.title) Widget"
        }
    }

    var summary: String {
        switch self {
        case .launchpad:
            "Docky's fullscreen app launcher, its layout controls, and optional global shortcut."
        case .windowSwitcher:
            "Docky's global Cmd-Tab-style window switcher and its in-place preview."
        case .customAppIcons:
            "Per-app icon overrides for pinned, running, and widget-backed apps."
        case .groupedAppFolders:
            "Show running apps inline beside app folders and reflect their open state."
        case .scriptedActions:
            "Catalog-backed AppleScript and menu-click actions for curated automation."
        case .smartStack:
            "Stacks available widgets into a single tile you can scroll through in the dock."
        case .widget(let kind):
            "Adds the \(kind.title) widget to the dock or shows it in place of a supported app icon."
        }
    }

    var requiredTier: ProductTier {
        switch self {
        case .launchpad, .windowSwitcher, .customAppIcons, .groupedAppFolders, .scriptedActions, .smartStack:
            .pro
        case .widget:
            .free
        }
    }

    var supportsLockedExistingPlacement: Bool {
        switch self {
        case .launchpad, .smartStack, .widget:
            true
        case .windowSwitcher, .customAppIcons, .groupedAppFolders, .scriptedActions:
            false
        }
    }
}

extension WidgetKind {
    nonisolated var productFeature: ProductFeature {
        .widget(self)
    }
}

extension DockEditPaletteItem {
    nonisolated var productFeature: ProductFeature? {
        switch self {
        case .launchpad:
            .launchpad
        case .widget(_, let kind):
            kind.productFeature
        case .smartStack:
            .smartStack
        case .spacer, .divider:
            nil
        }
    }
}

enum ProductRegistrationStatus: Equatable {
    case unregistered
    case savedForVerification
    case verified(ProductTier)

    var title: String {
        switch self {
        case .unregistered:
            "Not Registered"
        case .savedForVerification:
            "Registration Saved"
        case .verified(let tier):
            "Registered: \(tier.title)"
        }
    }

    var message: String {
        switch self {
        case .unregistered:
            "Register Docky Pro to unlock premium features."
        case .savedForVerification:
            "Your registration details are saved on this Mac."
        case .verified(let tier):
            "This Mac is unlocked for Docky \(tier.title)."
        }
    }
}

final class ProductService: ObservableObject {
    static let shared = ProductService()

    @Published var registeredEmail: String {
        didSet {
            let trimmed = registeredEmail.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed != oldValue else { return }
            if registeredEmail != trimmed {
                registeredEmail = trimmed
                return
            }
            defaults.set(trimmed, forKey: Keys.registeredEmail)
            refreshRegistrationStatus()
        }
    }

    @Published private(set) var currentTier: ProductTier {
        didSet {
            guard currentTier != oldValue else { return }
            defaults.set(currentTier.rawValue, forKey: Keys.currentTier)
        }
    }

    @Published private(set) var registrationStatus: ProductRegistrationStatus = .unregistered
    @Published private(set) var hasStoredLicenseKey = false

    private let defaults: UserDefaults

    private enum Keys {
        static let registeredEmail = "docky.product.registeredEmail"
        static let currentTier = "docky.product.currentTier"
        static let keychainService = "gt.quintero.Docky.product"
        static let keychainAccount = "gumroad-license-key"
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.registeredEmail = defaults.string(forKey: Keys.registeredEmail) ?? ""
        self.currentTier = defaults.string(forKey: Keys.currentTier)
            .flatMap(ProductTier.init(rawValue:)) ?? .free
        self.hasStoredLicenseKey = Self.readLicenseKey() != nil
        refreshRegistrationStatus()
    }

    func availability(
        for feature: ProductFeature,
        context: ProductFeatureContext = .standard
    ) -> ProductAvailability {
        if currentTier == .pro || feature.requiredTier == .free {
            return .available
        }

        if context == .existingPlacement, feature.supportsLockedExistingPlacement {
            return .lockedExisting
        }

        return .unavailableForNewPlacement
    }

    func isUnlocked(_ feature: ProductFeature) -> Bool {
        availability(for: feature).isUnlocked
    }

    func registerProduct(email: String, licenseKey: String) {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLicenseKey = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedEmail.isEmpty, !trimmedLicenseKey.isEmpty else {
            return
        }

        registeredEmail = trimmedEmail
        Self.writeLicenseKey(trimmedLicenseKey)
        hasStoredLicenseKey = true
        refreshRegistrationStatus()
    }

    func clearRegistration() {
        registeredEmail = ""
        currentTier = .free
        Self.deleteLicenseKey()
        hasStoredLicenseKey = false
        refreshRegistrationStatus()
    }

    func applyVerifiedTier(_ tier: ProductTier) {
        currentTier = tier
        refreshRegistrationStatus()
    }

    private func refreshRegistrationStatus() {
        if currentTier == .pro {
            registrationStatus = .verified(.pro)
            return
        }

        if !registeredEmail.isEmpty, hasStoredLicenseKey {
            registrationStatus = .savedForVerification
            return
        }

        registrationStatus = .unregistered
    }

    @discardableResult
    private static func writeLicenseKey(_ licenseKey: String) -> Bool {
        guard let data = licenseKey.data(using: .utf8) else {
            return false
        }

        let query = keychainQuery()
        SecItemDelete(query as CFDictionary)

        var item = query
        item[kSecValueData as String] = data
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    private static func readLicenseKey() -> String? {
        var query = keychainQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else {
            return nil
        }

        return value
    }

    private static func deleteLicenseKey() {
        SecItemDelete(keychainQuery() as CFDictionary)
    }

    private static func keychainQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Keys.keychainService,
            kSecAttrAccount as String: Keys.keychainAccount
        ]
    }
}
