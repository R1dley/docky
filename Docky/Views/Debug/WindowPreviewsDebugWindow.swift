//
//  WindowPreviewsDebugWindow.swift
//  Docky
//
//  DEBUG-only inspector for `WindowRegistry` + `WorkspaceService`'s
//  per-window thumbnail cache. Surfaces every observed `AppWindow`
//  alongside the thumbnail Docky is currently rendering for it, so
//  visual oddities (the menu-bar capture standing in for an app's
//  real content, stale thumbnails after window moves, etc.) can be
//  triaged at a glance.
//
//  Opened from the debug status menu's "Window Previews…" entry.
//

#if DEBUG

import AppKit
import Combine
import SwiftUI

@MainActor
final class WindowPreviewsDebugWindowController: NSWindowController {
    static let shared = WindowPreviewsDebugWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Window Previews (Debug)"
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentView = NSHostingView(rootView: WindowPreviewsDebugView())
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not available")
    }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct WindowPreviewsDebugView: View {
    @ObservedObject private var registry = WindowRegistry.shared
    @ObservedObject private var workspace = WorkspaceService.shared
    @State private var search = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if filteredWindows.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredWindows) { window in
                            row(for: window)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                            Divider()
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Tracked windows")
                    .font(.headline)
                Text(summaryLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                workspace.forceRefreshWindowPreviews()
            } label: {
                Label("Force Refresh", systemImage: "arrow.clockwise")
            }
            TextField("Filter…", text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "macwindow")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text(registry.windows.isEmpty ? "No tracked windows." : "No matches.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var summaryLine: String {
        let total = registry.windows.count
        let visible = registry.visible.count
        let minimized = registry.minimized.count
        let visiblePreviews = workspace.appWindowPreviews.count
        let minimizedPreviews = workspace.minimizedWindowPreviews.count
        return "\(total) total · \(visible) visible (\(visiblePreviews) cached) · \(minimized) minimized (\(minimizedPreviews) cached)"
    }

    private var filteredWindows: [AppWindow] {
        guard !search.isEmpty else { return registry.windows }
        let needle = search.lowercased()
        return registry.windows.filter { window in
            window.appDisplayName.lowercased().contains(needle)
                || window.bundleIdentifier.lowercased().contains(needle)
                || window.windowTitle.lowercased().contains(needle)
                || window.windowIdentifier.lowercased().contains(needle)
                || window.cgWindowID.map { "\($0)".contains(needle) } ?? false
        }
    }

    @ViewBuilder
    private func row(for window: AppWindow) -> some View {
        let cached = thumbnailImage(for: window)
        HStack(alignment: .top, spacing: 12) {
            Button {
                if let cached {
                    WindowPreviewQuickLookController.shared.show(
                        image: cached,
                        title: window.windowTitle.isEmpty
                            ? window.appDisplayName
                            : "\(window.appDisplayName) – \(window.windowTitle)"
                    )
                }
            } label: {
                thumbnail(for: window)
                    .frame(width: 180, height: 112)
                    .background(Color.black.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .help(cached == nil ? "No preview to expand" : "Click to view full-size")
            .disabled(cached == nil)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(window.appDisplayName)
                        .font(.headline)
                    if window.isMinimized {
                        Text("MINIMIZED")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.25), in: Capsule())
                    }
                    Spacer(minLength: 0)
                    Button {
                        copyDebugDescription(for: window)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .labelStyle(.iconOnly)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.borderless)
                    .help("Copy this row's debug description to the clipboard")
                }
                Text(window.windowTitle.isEmpty ? "(no title)" : window.windowTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 1) {
                    label("Bundle", window.bundleIdentifier)
                    label("PID", "\(window.processIdentifier)")
                    label("WindowID", window.cgWindowID.map { "\($0)" } ?? "—")
                    label("WindowNumber", window.windowNumber.map { "\($0)" } ?? "—")
                    label("Frame (AX)", window.frame.map(formatRect) ?? "—")
                    label("Frame (CG)", cgWindowFrameDescription(for: window))
                    label("Identifier", window.windowIdentifier)
                    label("Cached preview", cachedPreviewKindLabel(for: window))
                    if let cached {
                        label("Image size", formatImageSize(cached))
                        if let warning = captureShapeWarning(image: cached, frame: window.frame) {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text(warning)
                                    .foregroundStyle(.orange)
                            }
                            .font(.system(size: 11))
                        }
                    }
                }
                .font(.system(size: 11).monospaced())
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func thumbnail(for window: AppWindow) -> some View {
        if let image = thumbnailImage(for: window) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 4) {
                Image(systemName: "questionmark.square.dashed")
                    .font(.system(size: 24))
                    .foregroundStyle(.tertiary)
                Text("no preview")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                Text(noPreviewReason(for: window))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Walks the same gates `WorkspaceService.refreshAppWindowPreviews`
    /// (and the minimized path) does and reports the first one that
    /// blocked a capture for this specific window — so the debug
    /// row tells you *why* the thumbnail is missing instead of just
    /// "no preview". Order matches the actual production code paths.
    private func noPreviewReason(for window: AppWindow) -> String {
        if PermissionsService.shared.screenCapture != .granted {
            return "Screen Recording permission not granted"
        }
        if window.isMinimized {
            // Minimized-preview path doesn't track an attempted-IDs
            // set — captures fire opportunistically as windows
            // minimize. Cache miss here just means we haven't
            // captured it yet (e.g. minimized before Docky launched).
            return "Minimized — not yet captured"
        }
        if !ProductService.shared.isUnlocked(.windowSwitcher) {
            return "App-window previews gated by Pro (.windowSwitcher)"
        }
        // Window must be in the visible filter (non-minimized AND
        // large enough) to enter `refreshAppWindowPreviews`.
        if let frame = window.frame {
            let minimumTrackedSide: CGFloat = 100 // mirrors WindowRegistry
            if frame.width < minimumTrackedSide || frame.height < minimumTrackedSide {
                return "Frame below 100×100 — registry skips it"
            }
        }
        if !WindowRegistry.shared.visible.contains(where: { $0.id == window.id }) {
            return "Not in `visible` snapshot (filtered out)"
        }
        return "Capture pending or skipped (refresh hasn't completed yet)"
    }

    private func thumbnailImage(for window: AppWindow) -> NSImage? {
        if window.isMinimized {
            return workspace.minimizedWindowPreviews[window.windowIdentifier]
        }
        return workspace.appWindowPreviews[window.windowIdentifier]
    }

    private func cachedPreviewKindLabel(for window: AppWindow) -> String {
        if window.isMinimized {
            return workspace.minimizedWindowPreviews[window.windowIdentifier] != nil
                ? "minimized cache" : "—"
        }
        return workspace.appWindowPreviews[window.windowIdentifier] != nil
            ? "app-window cache" : "—"
    }

    /// Looks up the OS-reported bounds of `window.cgWindowID` via
    /// `CGWindowListCopyWindowInfo`. If this disagrees with the
    /// AX-reported frame, `_AXUIElementGetWindow` handed us a
    /// CGWindowID that doesn't actually point at the AX element's
    /// content window — common with apps that own auxiliary overlay
    /// windows (Simulator's pill chrome, browsers' picker popovers,
    /// etc.).
    private func cgWindowFrameDescription(for window: AppWindow) -> String {
        guard window.cgWindowID != nil else { return "—" }
        guard let rect = cgWindowFrame(for: window) else { return "(not found)" }
        return formatRect(rect)
    }

    private func cgWindowFrame(for window: AppWindow) -> CGRect? {
        guard let cgID = window.cgWindowID else { return nil }
        let descriptions = CGWindowListCopyWindowInfo(
            [.optionIncludingWindow],
            cgID
        ) as? [[String: Any]] ?? []
        guard let entry = descriptions.first,
              let boundsDict = entry[kCGWindowBounds as String] as? [String: Any] else {
            return nil
        }
        return CGRect(
            x: (boundsDict["X"] as? CGFloat) ?? 0,
            y: (boundsDict["Y"] as? CGFloat) ?? 0,
            width: (boundsDict["Width"] as? CGFloat) ?? 0,
            height: (boundsDict["Height"] as? CGFloat) ?? 0
        )
    }

    private func formatRect(_ rect: CGRect) -> String {
        "(\(Int(rect.minX)),\(Int(rect.minY))) \(Int(rect.width))×\(Int(rect.height))"
    }

    /// Native pixel dimensions of the cached image when available
    /// (falls back to point size). Helpful for spotting a captured
    /// thumbnail that's actually the menu bar — a long horizontal
    /// strip rather than a window-shaped rectangle.
    /// Builds a paste-friendly, multi-line dump of every diagnostic
    /// field shown in the row (and a few derived flags like the
    /// no-preview reason or the menu-bar-shape warning) and copies
    /// it to the general pasteboard.
    private func copyDebugDescription(for window: AppWindow) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(debugDescription(for: window), forType: .string)
    }

    private func debugDescription(for window: AppWindow) -> String {
        var lines: [String] = []
        lines.append("App:           \(window.appDisplayName)")
        lines.append("Bundle:        \(window.bundleIdentifier)")
        lines.append("PID:           \(window.processIdentifier)")
        lines.append("Title:         \(window.windowTitle.isEmpty ? "(no title)" : window.windowTitle)")
        lines.append("Identifier:    \(window.windowIdentifier)")
        lines.append("CGWindowID:    \(window.cgWindowID.map { "\($0)" } ?? "—")")
        lines.append("WindowNumber:  \(window.windowNumber.map { "\($0)" } ?? "—")")
        lines.append("Frame (AX):    \(window.frame.map(formatRect) ?? "—")")
        lines.append("Frame (CG):    \(cgWindowFrameDescription(for: window))")
        lines.append("Minimized:     \(window.isMinimized ? "yes" : "no")")
        lines.append("Cache:         \(cachedPreviewKindLabel(for: window))")

        if let image = thumbnailImage(for: window) {
            lines.append("Image size:    \(formatImageSize(image))")
            if let warning = captureShapeWarning(image: image, frame: window.frame) {
                lines.append("Warning:       \(warning)")
            }
        } else {
            lines.append("No-preview:    \(noPreviewReason(for: window))")
        }

        lines.append("Permissions:   screen=\(PermissionsService.shared.screenCapture)")
        lines.append("Pro:           windowSwitcher=\(ProductService.shared.isUnlocked(.windowSwitcher))")

        return lines.joined(separator: "\n")
    }

    private func formatImageSize(_ image: NSImage) -> String {
        if let rep = image.representations.first as? NSBitmapImageRep {
            return "\(rep.pixelsWide)×\(rep.pixelsHigh) px"
        }
        let size = image.size
        return "\(Int(size.width))×\(Int(size.height)) pt (no bitmap rep)"
    }

    /// Heuristic check: if the captured image's aspect ratio differs
    /// dramatically from the window's frame, the capture probably
    /// landed on the wrong target — typically the app's menu bar
    /// (very wide / very short) rather than the content window.
    private func captureShapeWarning(image: NSImage, frame: CGRect?) -> String? {
        let pixelSize: CGSize
        if let rep = image.representations.first as? NSBitmapImageRep {
            pixelSize = CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        } else {
            pixelSize = image.size
        }
        guard pixelSize.height > 0 else { return "Zero-height capture" }
        let imageRatio = pixelSize.width / pixelSize.height

        // Independent menu-bar shape detection: anything wider than
        // 8:1 is almost certainly a horizontal strip and not a real
        // window. macOS menu-bar windows are typically ~screen-wide
        // by ~24 pt.
        if imageRatio > 8 || pixelSize.height < 60 {
            return "Looks like a menu-bar capture (\(Int(pixelSize.width))×\(Int(pixelSize.height)))"
        }

        guard let frame, frame.height > 0, frame.width > 0 else { return nil }
        let frameRatio = frame.width / frame.height
        // If the captured aspect ratio is more than 3× off the
        // window's, it's a strong signal the capture is the wrong
        // surface.
        let ratio = imageRatio / frameRatio
        if ratio > 3 || ratio < (1.0 / 3.0) {
            return "Aspect mismatch (image \(String(format: "%.2f", imageRatio)) vs frame \(String(format: "%.2f", frameRatio)))"
        }
        return nil
    }

    @ViewBuilder
    private func label(_ key: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text("\(key):")
                .frame(width: 110, alignment: .trailing)
                .foregroundStyle(.tertiary)
            Text(value)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}

/// Quick Look-ish full-size preview for a captured window thumbnail.
/// A borderless transient panel that fills most of the screen with
/// the image at native resolution; click anywhere outside the image
/// or press Esc to dismiss.
@MainActor
final class WindowPreviewQuickLookController: NSWindowController {
    static let shared = WindowPreviewQuickLookController()

    private var keyMonitor: Any?

    private init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = NSColor.black.withAlphaComponent(0.85)
        panel.hasShadow = true
        panel.level = .floating
        panel.titleVisibility = .hidden
        super.init(window: panel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not available")
    }

    func show(image: NSImage, title: String) {
        guard let window else { return }

        // Size the panel to roughly the screen's working area while
        // leaving a comfortable margin, but never larger than the
        // image's native size (no upscaling artifacts).
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let maxSize = NSSize(
            width: min(screenFrame.width * 0.85, image.size.width + 80),
            height: min(screenFrame.height * 0.85, image.size.height + 80)
        )
        let origin = NSPoint(
            x: screenFrame.midX - maxSize.width / 2,
            y: screenFrame.midY - maxSize.height / 2
        )
        window.setFrame(NSRect(origin: origin, size: maxSize), display: true)

        window.contentView = NSHostingView(
            rootView: QuickLookContent(image: image, title: title) { [weak self] in
                self?.dismiss()
            }
        )

        installKeyMonitor()
        window.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        guard let window else { return }
        removeKeyMonitor()
        window.orderOut(nil)
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 { // Esc
                self?.dismiss()
                return nil
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }
}

private struct QuickLookContent: View {
    let image: NSImage
    let title: String
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }

            VStack(spacing: 8) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(20)

                Text(title)
                    .font(.callout)
                    .foregroundStyle(.white)
                    .padding(.bottom, 12)
            }
            .allowsHitTesting(false)
        }
    }
}

#endif
