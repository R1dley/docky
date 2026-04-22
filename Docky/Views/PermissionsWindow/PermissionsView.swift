//
//  PermissionsView.swift
//  Docky
//

import AppKit
import SwiftUI

struct PermissionsView: View {
    @ObservedObject private var service = PermissionsService.shared
    @State private var currentIndex = 0

    let steps: [Permission]
    let onComplete: () -> Void

    private var step: Permission { steps[currentIndex] }
    private var status: PermissionStatus { service.status(for: step) }
    private var isLastStep: Bool { currentIndex == steps.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            topSection
            bottomSection
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(width: 720, height: 620)
        .ignoresSafeArea(.container, edges: .top)
        .onAppear { service.refresh() }
        .task(id: currentIndex) {
            if (step == .finderAutomation || step == .location), status == .notDetermined {
                _ = await service.requestPermission(for: step)
            }

            await pollUntilAdvance()
        }
    }

    private var topSection: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: heroGradient,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 20) {
                HStack(spacing: 12) {
                    Image(systemName: stepSymbolName)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.16))
                        )

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Welcome to Docky")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                        Text(step.title)
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(.white)
                    }

                    Spacer()

//                    statusBadge
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text(step.explanation)
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)

//                    HStack(spacing: 10) {
//                        Image(systemName: "sparkles.rectangle.stack")
//                            .foregroundStyle(.white.opacity(0.9))
//                        Text(stepSummary)
//                            .font(.system(size: 14, weight: .medium))
//                            .foregroundStyle(.white.opacity(0.88))
//                        Spacer()
//                    }
                }
                
                Spacer()

                PageDots(totalPages: steps.count, currentIndex: currentIndex)
            }
            .padding(.horizontal, 32)
            .padding(.top, 80)
            .padding(.bottom, 26)
        }
    }

    private var bottomSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Grant Access")
                    .font(.title2.weight(.bold))

                Text(bottomSummary)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if showsAppDragProxy {
                draggableAppProxy
            }

            grantActions

            Spacer(minLength: 0)

            footer
        }
        .padding(.horizontal, 32)
        .padding(.top, 28)
        .padding(.bottom, 30)
    }

    @ViewBuilder
    private var grantActions: some View {
        HStack(spacing: 12) {
            Button(systemSettingsButtonTitle) {
                service.openSystemSettings(for: step)
            }
            .buttonStyle(.borderedProminent)

            if step == .finderAutomation || step == .screenCapture || step == .location {
                requestButton
            }
        }
    }

    private var showsAppDragProxy: Bool {
        true
    }

    private var draggableAppProxy: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Drag Docky into the list in System Settings to add it without searching.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: dockyAppURL.path))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Docky.app")
                        .font(.headline)
                    Text("Drag this into the macOS privacy list")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "hand.draw")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.15))
            )
            .onDrag {
                NSItemProvider(object: dockyAppURL as NSURL)
            }
        }
        .padding(.top, 4)
    }

    private var dockyAppURL: URL {
        Bundle.main.bundleURL
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Re-check") { service.refresh() }
            Spacer()
            Button(primaryActionTitle) { advance() }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
        }
    }

    private var grantMethodLabel: String? {
        switch grantMethod {
        case .fullDiskAccess: return "Full Disk Access"
        case .automation: return "Automation"
        case .accessibility: return "Accessibility"
        case .screenCapture: return "Screen Recording"
        case .location: return "Location"
        case .none: return nil
        }
    }

    @ViewBuilder
    private var requestButton: some View {
        if step == .finderAutomation || step == .screenCapture || step == .location {
            Button(requestButtonTitle) {
                Task {
                    _ = await service.requestPermission(for: step)
                }
            }
            .buttonStyle(.bordered)
        }
    }

    private var grantMethod: GrantMethod? {
        switch step {
        case .userFolders:
            return service.userFoldersGrantMethod
        case .finderAutomation:
            return service.finderAutomationGrantMethod
        case .accessibility:
            return service.accessibilityGrantMethod
        case .screenCapture:
            return service.screenCaptureGrantMethod
        case .location:
            return service.locationGrantMethod
        }
    }

    private var systemSettingsButtonTitle: String {
        switch step {
        case .finderAutomation:
            return "Open System Settings (Automation)"
        case .userFolders:
            return "Open System Settings (Full Disk Access)"
        case .accessibility:
            return "Open System Settings (Accessibility)"
        case .screenCapture:
            return "Open System Settings (Screen Recording)"
        case .location:
            return "Open System Settings (Location Services)"
        }
    }

    private var requestButtonTitle: String {
        switch step {
        case .finderAutomation:
            return "Request Finder Access"
        case .screenCapture:
            return "Request Screen Recording Access"
        case .location:
            return "Request Location Access"
        case .userFolders, .accessibility:
            return "Request Access"
        }
    }

    private var statusIcon: String {
        switch status {
        case .granted: return "checkmark.circle.fill"
        case .denied: return "exclamationmark.triangle.fill"
        case .notDetermined: return "circle"
        }
    }

    private var statusColor: Color {
        switch status {
        case .granted: return .green
        case .denied: return .orange
        case .notDetermined: return .secondary
        }
    }

    private var primaryActionTitle: String {
        if status == .granted {
            return isLastStep ? "Continue" : "Next"
        }

        return isLastStep ? "Skip" : "Skip"
    }

    private func advance() {
        if isLastStep {
            onComplete()
        } else {
            currentIndex += 1
        }
    }

    private func advanceIfReady() {
        guard status == .granted else { return }
        advance()
    }

    private func pollUntilAdvance() async {
        advanceIfReady()

        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }

            service.refresh()
            if status == .granted {
                advance()
                return
            }
        }
    }

    private var heroGradient: [Color] {
        switch step {
        case .userFolders:
            return [Color(red: 0.29, green: 0.46, blue: 0.96), Color(red: 0.15, green: 0.14, blue: 0.48)]
        case .finderAutomation:
            return [Color(red: 0.27, green: 0.68, blue: 0.98), Color(red: 0.12, green: 0.31, blue: 0.68)]
        case .accessibility:
            return [Color(red: 0.66, green: 0.39, blue: 0.98), Color(red: 0.24, green: 0.14, blue: 0.56)]
        case .screenCapture:
            return [Color(red: 0.10, green: 0.70, blue: 0.63), Color(red: 0.07, green: 0.28, blue: 0.45)]
        case .location:
            return [Color(red: 1.00, green: 0.53, blue: 0.40), Color(red: 0.60, green: 0.19, blue: 0.21)]
        }
    }

    private var stepSymbolName: String {
        switch step {
        case .userFolders:
            return "folder.badge.gearshape"
        case .finderAutomation:
            return "apple.terminal.on.rectangle"
        case .accessibility:
            return "figure.wave.circle"
        case .screenCapture:
            return "rectangle.on.rectangle"
        case .location:
            return "location.circle"
        }
    }

    private var stepSummary: String {
        switch status {
        case .granted:
            return "This permission is already enabled. You can continue when ready."
        case .denied:
            return "macOS has this disabled right now. Open System Settings, enable it, then come back and re-check."
        case .notDetermined:
            return "Docky will guide you through the fastest way to enable this on your Mac."
        }
    }

    private var bottomSummary: String {
        if step.isRequiredAtLaunch {
            return "This permission unlocks a core Docky feature, but you can skip it for now and grant it later."
        }

        return "This permission unlocks an optional feature and can be granted later from Settings."
    }

    private var statusBadge: some View {
        Label(statusLabel, systemImage: statusIcon)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(statusBadgeColor.opacity(0.28), in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(0.16))
            )
    }

    private var statusLabel: String {
        switch status {
        case .granted:
            return "Granted"
        case .denied:
            return "Needs Attention"
        case .notDetermined:
            return "Not Yet Granted"
        }
    }

    private var statusBadgeColor: Color {
        switch status {
        case .granted:
            return .green
        case .denied:
            return .orange
        case .notDetermined:
            return .white
        }
    }
}

private struct PageDots: View {
    let totalPages: Int
    let currentIndex: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalPages, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(index == currentIndex ? Color.white.opacity(0.95) : Color.white.opacity(0.30))
                    .frame(width: index == currentIndex ? 24 : 8, height: 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(currentIndex + 1) of \(max(totalPages, 1))")
    }
}
