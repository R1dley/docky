//
//  NowPlayingWidgetTileView.swift
//  Docky
//

import AppKit
import CoreImage
import SwiftUI

struct NowPlayingWidgetTileView: View {
    let tile: WidgetTile
    let usesOuterPadding: Bool
    @ObservedObject private var mediaPlayback = MediaPlaybackService.shared
    @State private var isHovering = false

    var body: some View {
        ZStack {
            WidgetMaterialBackground(cornerRadius: 12)

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: prominentTintColor).opacity(0.36))

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)

            content
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(usesOuterPadding ? 8 : 0)
    }

    @ViewBuilder
    private var content: some View {
        if playbackState?.hasContent != true {
            notPlayingState
        } else {
            switch tile.span {
            case .one:
                nowPlayingOneUp
            case .two:
                nowPlayingTwoUp
            case .three:
                nowPlayingThreeUp
            }
        }
    }

    private var notPlayingState: some View {
        VStack(spacing: 4) {
            if tile.span == .one {
                Image(systemName: "music.note")
                    .opacity(0.25)
                    .font(.title)
            } else {
                Text("Not Playing")
                    .font(.system(size: 13, weight: .semibold))
            }
        }
        .foregroundStyle(primaryForegroundColor)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(10)
    }

    private var nowPlayingOneUp: some View {
        artworkView(size: nil)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if isHovering {
                    ZStack {
                        Color.black.opacity(0.18)

                        Image(systemName: playbackState?.isPlaying == true ? "pause.fill" : "play.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.95))
                    }
                    .transition(.opacity)
                }
            }
            .onHover { isHovering = $0 }
    }

    private var nowPlayingTwoUp: some View {
        HStack(spacing: 12) {
            artworkView(size: 52)
            HStack(spacing: 10) {
                controlButton("backward.fill", action: skipToPrevious)
                controlButton(
                    playbackState?.isPlaying == true ? "pause.fill" : "play.fill",
                    action: togglePlayPause
                )
                controlButton("forward.fill", action: skipToNext)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var nowPlayingThreeUp: some View {
        HStack(spacing: 12) {
            artworkView(size: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text(playbackTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(primaryForegroundColor)
                    .lineLimit(1)

                Text(playbackArtist)
                    .font(.caption2)
                    .foregroundStyle(secondaryForegroundColor)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                controlButton(
                    playbackState?.isPlaying == true ? "pause.fill" : "play.fill",
                    action: togglePlayPause
                )
                controlButton("forward.fill", action: skipToNext)
            }
            .padding(.trailing, 2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func artworkView(size: CGFloat?) -> some View {
        if let artworkData = playbackState?.artworkData,
           let artworkImage = NSImage(data: artworkData) {
            Image(nsImage: artworkImage)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size == nil ? 12 : 8, style: .continuous))
        } else {
            Image(nsImage: IconCacheService.shared.icon(forBundleIdentifier: tile.ownerBundleIdentifier))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: size == nil ? .fill : .fit)
                .frame(width: size, height: size)
        }
    }

    private func controlButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(primaryForegroundColor)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var playbackState: MediaPlaybackState? {
        mediaPlayback.state(for: tile.ownerBundleIdentifier)
    }

    private var prominentTintColor: NSColor {
        if let artworkData = playbackState?.artworkData,
           let artworkImage = NSImage(data: artworkData),
           let extractedColor = Self.prominentColor(from: artworkImage) {
            return extractedColor.usingColorSpace(.deviceRGB) ?? extractedColor
        }

        return (NSColor.windowBackgroundColor.blended(withFraction: 0.18, of: .black) ?? .windowBackgroundColor)
    }

    private var usesDarkForeground: Bool {
        prominentTintColor.perceivedLuminance > 0.62
    }

    private var primaryForegroundColor: Color {
        Color(nsColor: usesDarkForeground ? .black.withAlphaComponent(0.82) : .white.withAlphaComponent(0.96))
    }

    private var secondaryForegroundColor: Color {
        Color(nsColor: usesDarkForeground ? .black.withAlphaComponent(0.56) : .white.withAlphaComponent(0.72))
    }

    private var ownerDisplayName: String {
        playbackState?.displayName
            ?? (NSWorkspace.shared.urlForApplication(withBundleIdentifier: tile.ownerBundleIdentifier).map {
                FileManager.default.displayName(atPath: $0.path)
            } ?? tile.title)
    }

    private var playbackTitle: String {
        guard let playbackState, playbackState.hasContent else {
            return tile.title
        }

        return playbackState.title.isEmpty ? ownerDisplayName : playbackState.title
    }

    private var playbackArtist: String {
        guard let playbackState, playbackState.hasContent else {
            return ownerDisplayName
        }

        if !playbackState.artist.isEmpty {
            return playbackState.artist
        }

        return ownerDisplayName
    }

    private func togglePlayPause() {
        Task {
            await mediaPlayback.togglePlayPause(for: tile.ownerBundleIdentifier)
        }
    }

    private func skipToNext() {
        Task {
            await mediaPlayback.skipToNext(for: tile.ownerBundleIdentifier)
        }
    }

    private func skipToPrevious() {
        Task {
            await mediaPlayback.skipToPrevious(for: tile.ownerBundleIdentifier)
        }
    }

    private static let ciContext = CIContext(options: nil)

    private static func prominentColor(from image: NSImage) -> NSColor? {
        guard let tiffData = image.tiffRepresentation,
              let ciImage = CIImage(data: tiffData) else {
            return nil
        }

        let extent = ciImage.extent
        guard !extent.isEmpty,
              let filter = CIFilter(name: "CIAreaAverage") else {
            return nil
        }

        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: extent), forKey: kCIInputExtentKey)

        guard let outputImage = filter.outputImage else {
            return nil
        }

        var rgba = [UInt8](repeating: 0, count: 4)
        ciContext.render(
            outputImage,
            toBitmap: &rgba,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        let baseColor = NSColor(
            red: CGFloat(rgba[0]) / 255,
            green: CGFloat(rgba[1]) / 255,
            blue: CGFloat(rgba[2]) / 255,
            alpha: 1
        )

        return baseColor.withSystemEffect(.pressed)
    }
}

private struct WidgetMaterialBackground: NSViewRepresentable {
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .withinWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.wantsLayer = true
        nsView.layer?.cornerCurve = .continuous
        nsView.layer?.cornerRadius = cornerRadius
        nsView.layer?.masksToBounds = true
    }
}

private extension NSColor {
    var perceivedLuminance: CGFloat {
        guard let rgbColor = usingColorSpace(.deviceRGB) else {
            return 0
        }

        return (0.2126 * rgbColor.redComponent) + (0.7152 * rgbColor.greenComponent) + (0.0722 * rgbColor.blueComponent)
    }
}
