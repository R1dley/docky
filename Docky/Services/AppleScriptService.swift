//
//  AppleScriptService.swift
//  Docky
//
//  Finder-backed actions that are awkward or unavailable via NSWorkspace
//  alone. The sandboxed build relies on the app's Apple Events entitlement
//  and executes the script source directly, which avoids writing into the
//  Application Scripts container at runtime.
//

import AppKit
import Foundation

final class AppleScriptService {
    static let shared = AppleScriptService()

    private init() {}

    @discardableResult
    func requestFinderAutomationPermission() async -> Bool {
        await runFinderScript(.permissionProbe)
    }

    @discardableResult
    func revealInFinder(_ url: URL) async -> Bool {
        await runFinderScript(.reveal(url))
    }

    @discardableResult
    func openFinderWindow(for url: URL) async -> Bool {
        await runFinderScript(.openFolder(url))
    }

    @discardableResult
    func openTrash() async -> Bool {
        await runFinderScript(.openTrash)
    }

    @discardableResult
    func emptyTrash() async -> Bool {
        await runFinderScript(.emptyTrash)
    }

    private func runFinderScript(_ command: FinderCommand) async -> Bool {
        do {
            try execute(source: command.source)
            PermissionsService.shared.updateFinderAutomation(status: .granted)
            return true
        } catch let error as AppleScriptServiceError {
            handle(error)
            return false
        } catch {
            handle(.executionFailed(error.localizedDescription))
            return false
        }
    }

    private func execute(source: String) throws {
        guard let script = NSAppleScript(source: source) else {
            throw AppleScriptServiceError.compilationFailed
        }

        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)
        if let error = scriptError(from: errorInfo) {
            throw error
        }
    }

    private func scriptError(from errorInfo: NSDictionary?) -> AppleScriptServiceError? {
        guard let errorInfo else { return nil }
        let number = errorInfo[NSAppleScript.errorNumber] as? Int
        let message = (errorInfo[NSAppleScript.errorMessage] as? String) ?? "AppleScript execution failed."

        if number == -1743 {
            return .permissionDenied
        }
        return .executionFailed(message)
    }

    private func handle(_ error: AppleScriptServiceError) {
        switch error {
        case .permissionDenied:
            PermissionsService.shared.updateFinderAutomation(status: .denied)
            presentAlert(
                title: "Finder automation wasn’t allowed",
                body: "Allow Docky to control Finder in Privacy & Security > Automation, or use the Finder Automation row in Docky Settings to request access again."
            )
        case .compilationFailed:
            presentAlert(
                title: "Finder action failed",
                body: "Docky couldn't prepare the AppleScript needed for this Finder action."
            )
        case .executionFailed(let message):
            presentAlert(
                title: "Finder action failed",
                body: message
            )
        }
    }

    private func presentAlert(title: String, body: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.alertStyle = .warning
        alert.runModal()
    }
}

private enum FinderCommand {
    case permissionProbe
    case reveal(URL)
    case openFolder(URL)
    case openTrash
    case emptyTrash

    var source: String {
        switch self {
        case .permissionProbe:
            return """
            tell application id \"com.apple.finder\" to launch
            tell application id \"com.apple.finder\"
                count Finder windows
            end tell
            """
        case .reveal(let url):
            return """
            tell application id \"com.apple.finder\" to launch
            tell application id \"com.apple.finder\"
                activate
                reveal POSIX file "\(escapedPOSIXPath(url))"
            end tell
            """
        case .openFolder(let url):
            return """
            tell application id \"com.apple.finder\" to launch
            tell application id \"com.apple.finder\"
                activate
                open POSIX file "\(escapedPOSIXPath(url))"
            end tell
            """
        case .openTrash:
            return """
            tell application id \"com.apple.finder\" to launch
            tell application id \"com.apple.finder\"
                activate
                open trash
            end tell
            """
        case .emptyTrash:
            return """
            tell application id \"com.apple.finder\" to launch
            tell application id \"com.apple.finder\"
                activate
                empty the trash
            end tell
            """
        }
    }
}

private enum AppleScriptServiceError: Error {
    case permissionDenied
    case compilationFailed
    case executionFailed(String)
}

private func escapedPOSIXPath(_ url: URL) -> String {
    url.path
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
}
