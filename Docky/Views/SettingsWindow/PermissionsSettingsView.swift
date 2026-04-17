//
//  PermissionsSettingsView.swift
//  Docky
//

import SwiftUI

struct PermissionsSettingsView: View {
    @ObservedObject private var service = PermissionsService.shared

    var body: some View {
        Form {
            permissionSection(for: .dockSettings)
            permissionSection(for: .userFolders)
            permissionSection(for: .finderAutomation)

            Section {
                Button("Re-check Permissions") {
                    service.refresh()
                }
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func permissionSection(for permission: Permission) -> some View {
        Section(permission.title) {
            LabeledContent("Status") {
                Text(statusText(for: permission))
                    .foregroundStyle(statusColor(for: permission))
            }

            if let grantMethod = grantMethodText(for: permission) {
                LabeledContent("Access Via") {
                    Text(grantMethod)
                }
            }

            Text(permission.explanation)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                if !AppEnvironment.isSandboxed || permission == .finderAutomation {
                    Button("Open System Settings") {
                        service.openSystemSettings(for: permission)
                    }
                }

                requestButton(for: permission)

                if canRevokeUserSelectedFile(for: permission) {
                    Button("Revoke") {
                        service.revokeUserSelectedFile(for: permission)
                    }
                }

                if permission == .finderAutomation, service.finderAutomation != .notDetermined {
                    Button("Forget Status") {
                        service.clearAutomationStatus(for: permission)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func requestButton(for permission: Permission) -> some View {
        switch permission {
        case .dockSettings, .userFolders:
            Button(buttonTitle(for: permission)) {
                _ = service.requestUserSelectedFile(for: permission)
            }
        case .finderAutomation:
            Button(buttonTitle(for: permission)) {
                Task {
                    _ = await service.requestAutomationPermission(for: permission)
                }
            }
        }
    }

    private func statusText(for permission: Permission) -> String {
        switch service.status(for: permission) {
        case .granted: return "Granted"
        case .denied: return "Missing"
        case .notDetermined: return "Not Determined"
        }
    }

    private func statusColor(for permission: Permission) -> Color {
        switch service.status(for: permission) {
        case .granted: return .green
        case .denied: return .orange
        case .notDetermined: return .secondary
        }
    }

    private func grantMethodText(for permission: Permission) -> String? {
        switch grantMethod(for: permission) {
        case .fullDiskAccess: return "Full Disk Access"
        case .userSelectedFile: return permission == .dockSettings ? "User-selected file" : "User-selected folder"
        case .automation: return "Automation"
        case .none: return nil
        }
    }

    private func grantMethod(for permission: Permission) -> GrantMethod? {
        switch permission {
        case .dockSettings:
            return service.dockSettingsGrantMethod
        case .userFolders:
            return service.userFoldersGrantMethod
        case .finderAutomation:
            return service.finderAutomationGrantMethod
        }
    }

    private func canRevokeUserSelectedFile(for permission: Permission) -> Bool {
        grantMethod(for: permission) == .userSelectedFile
    }

    private func buttonTitle(for permission: Permission) -> String {
        switch permission {
        case .dockSettings: return "Select Dock Plist..."
        case .userFolders: return "Select Home Folder..."
        case .finderAutomation: return "Request Finder Access"
        }
    }
}
