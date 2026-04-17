//
//  PermissionsView.swift
//  Docky
//

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
        VStack(alignment: .leading, spacing: 20) {
            header
            content
            Spacer()
            grantActions
            footer
        }
        .padding(28)
        .frame(width: 520, height: 420)
        .onAppear { service.refresh() }
        .task(id: currentIndex) {
            guard step == .finderAutomation, status == .notDetermined else { return }
            _ = await service.requestAutomationPermission(for: step)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Welcome to Docky")
                .font(.largeTitle.bold())
            Text("Step \(currentIndex + 1) of \(steps.count)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: statusIcon)
                    .font(.title2)
                    .foregroundStyle(statusColor)
                Text(step.title)
                    .font(.title2.bold())
                if let method = grantMethodLabel {
                    Text(method)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
            }
            Text(step.explanation)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var grantActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !AppEnvironment.isSandboxed || step == .finderAutomation {
                Button(systemSettingsButtonTitle) {
                    service.openSystemSettings(for: step)
                }
            }
            requestButton
            if status == .granted, grantMethod == .userSelectedFile {
                Button("Revoke file access") {
                    service.revokeUserSelectedFile(for: step)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Re-check") { service.refresh() }
            Spacer()
            Button(isLastStep ? "Continue" : "Next") { advance() }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(!canAdvance)
        }
    }

    private var grantMethodLabel: String? {
        switch grantMethod {
        case .fullDiskAccess: return "Full Disk Access"
        case .userSelectedFile:
            return step == .dockSettings ? "User-selected file" : "User-selected folder"
        case .automation: return "Automation"
        case .none: return nil
        }
    }

    @ViewBuilder
    private var requestButton: some View {
        switch step {
        case .dockSettings:
            Button("Select com.apple.dock.plist…") {
                _ = service.requestUserSelectedFile(for: step)
            }
        case .userFolders:
            Button("Select Home Folder…") {
                _ = service.requestUserSelectedFile(for: step)
            }
        case .finderAutomation:
            Button("Request Finder Access") {
                Task {
                    _ = await service.requestAutomationPermission(for: step)
                }
            }
        }
    }

    private var grantMethod: GrantMethod? {
        switch step {
        case .dockSettings:
            return service.dockSettingsGrantMethod
        case .userFolders:
            return service.userFoldersGrantMethod
        case .finderAutomation:
            return service.finderAutomationGrantMethod
        }
    }

    private var systemSettingsButtonTitle: String {
        switch step {
        case .finderAutomation:
            return "Open System Settings (Automation)"
        case .dockSettings, .userFolders:
            return "Open System Settings (Full Disk Access)"
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

    private var canAdvance: Bool {
        if step.isRequiredAtLaunch {
            return status == .granted
        }
        return status != .notDetermined
    }

    private func advance() {
        if isLastStep {
            onComplete()
        } else {
            currentIndex += 1
        }
    }
}
