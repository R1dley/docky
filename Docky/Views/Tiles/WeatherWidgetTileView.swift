//
//  WeatherWidgetTileView.swift
//  Docky
//

import AppKit
import CoreLocation
import SwiftUI

struct WeatherWidgetTileView: View {
    let tile: WidgetTile
    let cornerRadius: CGFloat
    let renderedSpan: TileSpan
    let isWithinStack: Bool

    @ObservedObject private var weather = WeatherService.shared

    var body: some View {
        GeometryReader { proxy in
            let layout = layout(in: proxy.size)

            ZStack {
                LinearGradient(
                    colors: backgroundColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius, style: .continuous))

                if !isWithinStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                }

                content(layout: layout)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task {
            weather.ensureFreshWeather()
        }
    }

    @ViewBuilder
    private func content(layout: LayoutMetrics) -> some View {
        if let snapshot = weather.snapshot {
            switch renderedSpan {
            case .one:
                oneUp(snapshot: snapshot, layout: layout)
            case .two:
                twoUp(snapshot: snapshot, layout: layout)
            case .three:
                threeUp(snapshot: snapshot, layout: layout)
            }
        } else {
            placeholder(layout: layout)
        }
    }

    private func oneUp(snapshot: WeatherSnapshot, layout: LayoutMetrics) -> some View {
        VStack(spacing: layout.stackSpacing) {
            Image(systemName: snapshot.symbolName)
                .font(.system(size: layout.symbolSize, weight: .semibold))
                .foregroundStyle(.white.opacity(0.96))
            Text(snapshot.roundedTemperatureText)
                .font(.system(size: layout.temperatureFontSize, weight: .bold))
        }
        .foregroundStyle(.white.opacity(0.96))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func twoUp(snapshot: WeatherSnapshot, layout: LayoutMetrics) -> some View {
        HStack(spacing: layout.contentGap) {
            Image(systemName: snapshot.symbolName)
                .font(.system(size: layout.symbolSize, weight: .semibold))
                .foregroundStyle(.white.opacity(0.96))

            VStack(alignment: .leading, spacing: layout.stackSpacing) {
                Text(snapshot.roundedTemperatureText)
                    .font(.system(size: layout.temperatureFontSize, weight: .bold))
                if !snapshot.highLowText.isEmpty {
                    Text(snapshot.highLowText)
                        .font(.system(size: layout.secondaryFontSize, weight: .medium))
                        .foregroundStyle(.white.opacity(0.74))
                }
            }

            Spacer(minLength: 0)
        }
        .foregroundStyle(.white.opacity(0.96))
        .padding(layout.contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func threeUp(snapshot: WeatherSnapshot, layout: LayoutMetrics) -> some View {
        HStack(spacing: layout.contentGap) {
            Image(systemName: snapshot.symbolName)
                .font(.system(size: layout.symbolSize, weight: .semibold))
                .foregroundStyle(.white.opacity(0.96))
                .frame(width: layout.leadingColumnWidth)

            VStack(alignment: .leading, spacing: layout.stackSpacing) {
                Text(snapshot.locationName)
                    .font(.system(size: layout.secondaryFontSize, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
                Text(snapshot.roundedTemperatureText)
                    .font(.system(size: layout.temperatureFontSize, weight: .bold))
                    .foregroundStyle(.white.opacity(0.97))
                Text(snapshot.conditionDescription)
                    .font(.system(size: layout.secondaryFontSize))
                    .foregroundStyle(.white.opacity(0.74))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if !snapshot.highLowText.isEmpty {
                Text(snapshot.highLowText)
                    .font(.system(size: layout.secondaryFontSize, weight: .medium))
                    .foregroundStyle(.white.opacity(0.78))
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(layout.contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func placeholder(layout: LayoutMetrics) -> some View {
        VStack(spacing: layout.stackSpacing) {
            if weather.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white.opacity(0.9))
                    .foregroundStyle(.white.opacity(0.9))
            } else {
                Image(systemName: placeholderSymbolName)
                    .font(.system(size: layout.symbolSize, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
            }

            Text(placeholderTitle)
                .font(.system(size: layout.secondaryFontSize, weight: .semibold))
                .foregroundStyle(.white.opacity(0.94))
                .lineLimit(1)

            if renderedSpan != .one, let lastErrorDescription = weather.lastErrorDescription {
                Text(lastErrorDescription)
                    .font(.system(size: max(layout.secondaryFontSize - 1, 9)))
                    .foregroundStyle(.white.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .lineLimit(renderedSpan == .two ? 2 : 1)
            }
        }
        .padding(layout.contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func layout(in size: CGSize) -> LayoutMetrics {
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        let minSide = min(width, height)
        let contentPadding = min(max(minSide * 0.12, 6), minSide * 0.18)
        let contentGap = min(max(minSide * 0.12, 6), minSide * 0.2)
        let stackSpacing = min(max(minSide * 0.05, 3), minSide * 0.09)

        return LayoutMetrics(
            contentPadding: contentPadding,
            contentGap: contentGap,
            stackSpacing: stackSpacing,
            symbolSize: min(max(minSide * 0.32, 18), 34),
            temperatureFontSize: min(max(minSide * 0.24, 14), renderedSpan == .one ? 26 : 24),
            secondaryFontSize: min(max(minSide * 0.13, 10), 13),
            leadingColumnWidth: min(max(minSide * 0.36, 24), 42)
        )
    }

    private var placeholderTitle: String {
        switch weather.authorizationStatus {
        case .denied, .restricted:
            "Enable Location"
        default:
            weather.isLoading ? "Loading Weather" : "Weather"
        }
    }

    private var placeholderSymbolName: String {
        switch weather.authorizationStatus {
        case .denied, .restricted:
            "location.slash.fill"
        default:
            "cloud.sun.fill"
        }
    }

    private var backgroundColors: [Color] {
        if let snapshot = weather.snapshot {
            switch snapshot.symbolName {
            case "sun.max.fill", "moon.stars.fill":
                return [Color(red: 0.25, green: 0.52, blue: 0.96), Color(red: 0.97, green: 0.64, blue: 0.28)]
            case "cloud.bolt.rain.fill":
                return [Color(red: 0.19, green: 0.24, blue: 0.41), Color(red: 0.35, green: 0.42, blue: 0.63)]
            case "cloud.rain.fill", "cloud.drizzle.fill", "cloud.snow.fill", "cloud.fog.fill":
                return [Color(red: 0.30, green: 0.39, blue: 0.56), Color(red: 0.46, green: 0.58, blue: 0.77)]
            default:
                return [Color(red: 0.28, green: 0.48, blue: 0.86), Color(red: 0.60, green: 0.76, blue: 0.96)]
            }
        }

        return [Color(red: 0.23, green: 0.38, blue: 0.67), Color(red: 0.52, green: 0.67, blue: 0.88)]
    }
}

private struct LayoutMetrics {
    let contentPadding: CGFloat
    let contentGap: CGFloat
    let stackSpacing: CGFloat
    let symbolSize: CGFloat
    let temperatureFontSize: CGFloat
    let secondaryFontSize: CGFloat
    let leadingColumnWidth: CGFloat
}
