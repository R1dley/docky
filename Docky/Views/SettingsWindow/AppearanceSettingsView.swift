//
//  AppearanceSettingsView.swift
//  Docky
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AppearanceSettingsView: View {
    enum Subsection {
        case general
        case indicators
        case tileLayout
        case windowShape
        case windowBackground
    }

    let subsection: Subsection

    @ObservedObject private var dockSettings = DockSettingsService.shared
    @Bindable private var preferences = DockyPreferences.shared
    @State private var isShowingResetConfirmation = false

    var body: some View {
        Form {
            switch subsection {
            case .general:
                generalSection
            case .indicators:
                indicatorsSection
            case .tileLayout:
                tileLayoutSection
            case .windowShape:
                windowShapeSection
            case .windowBackground:
                windowBackgroundSection
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Reset appearance settings?",
            isPresented: $isShowingResetConfirmation
        ) {
            Button("Reset Appearance", role: .destructive) {
                DockyPreferences.shared.resetAppearanceToDefaults()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Indicators, tile layout, window shape, window background, and the glass toggle will return to their defaults. App icons, behavior, widgets, and other settings are unaffected. This cannot be undone.")
        }
    }

    @ViewBuilder
    private var generalSection: some View {
        Section("Glass") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Disable Glass Look", isOn: $preferences.disablesGlassLook)
                    .font(.headline)

                Text("Removes the main window's glossy gradient border and Liquid Glass material while keeping the existing blur and background tinting.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
        }

        Section("Reset Appearance") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Restores the appearance preferences (indicators, tile layout, window shape, window background, glass) to their defaults. App icons, behavior, widgets, launchpad, and window-management settings keep their current values.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Reset Appearance", role: .destructive) {
                    isShowingResetConfirmation = true
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var indicatorsSection: some View {
        Section("Activity Indicator") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Active Indicator Shape")
                        .font(.headline)

                    Spacer()

                    Picker("Active Indicator Shape", selection: $preferences.activeIndicatorShape) {
                        ForEach(DockTileIndicatorShape.allCases) { shape in
                            Text(shape.title).tag(shape)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                if preferences.activeIndicatorShape == .image {
                    HStack {
                        Button("Choose Image...") {
                            chooseActiveIndicatorImage()
                        }

                        if preferences.activeIndicatorImagePath != nil {
                            Button("Clear") {
                                preferences.activeIndicatorImagePath = nil
                            }
                        }
                    }

                    if let selectedActiveIndicatorImageName {
                        Text(selectedActiveIndicatorImageName)
                            .foregroundStyle(.secondary)
                    }
                }

                if showsIndicatorColorControls {
                    Divider()

                    Toggle("Use Custom Indicator Color", isOn: usesCustomActiveIndicatorColorBinding)
                        .font(.headline)

                    if preferences.activeIndicatorColor != nil {
                        ColorPicker("Indicator Color", selection: activeIndicatorColorBinding, supportsOpacity: false)
                    }
                }

                Text("Choose whether running apps use no marker, the classic dot, a pill, or a custom image.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)

            sliderRow(
                title: "Inward Offset",
                value: $preferences.activeIndicatorOffset,
                range: -20...20,
                step: 1,
                format: { "\(Int($0)) pt" },
                description: "Shifts the indicator further from or closer to the screen edge."
            )

            sliderRow(
                title: "Size",
                value: $preferences.activeIndicatorScale,
                range: 0.5...2.0,
                step: 0.05,
                format: { String(format: "%.2fx", $0) },
                description: "Scales the indicator's rendered size."
            )
        }

        Section("Dividers") {
            customDividerImageControls
        }
    }

    @ViewBuilder
    private var customDividerImageControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Custom Divider Image")
                .font(.headline)

            dividerImageRow(
                title: "Center",
                path: preferences.dividerImagePath,
                onChoose: { chooseDividerImage(slot: .global) },
                onClear: { preferences.dividerImagePath = nil }
            )

            Divider()

            dividerImageRow(
                title: "Left Side",
                path: preferences.leftDividerImagePath,
                onChoose: { chooseDividerImage(slot: .left) },
                onClear: { preferences.leftDividerImagePath = nil }
            )

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Right Side")
                    Spacer()
                    Toggle("Mirror Left Side", isOn: $preferences.mirrorsLeftDividerOnRight)
                        .toggleStyle(.switch)
                }

                if !preferences.mirrorsLeftDividerOnRight {
                    dividerImageRow(
                        title: nil,
                        path: preferences.rightDividerImagePath,
                        onChoose: { chooseDividerImage(slot: .right) },
                        onClear: { preferences.rightDividerImagePath = nil }
                    )
                }
            }

            Text("Use a custom image for dividers. The center image applies to dividers near the middle of the dock; the left and right overrides target dividers near each end. Mirror reuses the left image flipped on the right side. In vertical docks the image is rotated 90° to follow the dock's axis.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)

        sliderRow(
            title: "Padding",
            value: $preferences.dividerPaddingFraction,
            range: 0...0.5,
            step: 0.01,
            format: { "\(Int(($0 * 100).rounded()))%" },
            description: "Controls how much each divider is inset along its short axis, as a fraction of the tile size."
        )

        sliderRow(
            title: "Vertical Offset",
            value: $preferences.dividerOffset,
            range: -20...20,
            step: 1,
            format: { "\(Int($0)) pt" },
            description: "Shifts dividers along the tile's short axis. Positive values move them up in horizontal docks or right in vertical docks."
        )

        sliderRow(
            title: "Image Size",
            value: $preferences.dividerImageScale,
            range: 0.5...2.0,
            step: 0.05,
            format: { String(format: "%.2fx", $0) },
            description: "Scales custom divider images. Has no effect on the default line."
        )
    }

    @ViewBuilder
    private func sliderRow(
        title: String,
        value: Binding<CGFloat>,
        range: ClosedRange<CGFloat>,
        step: CGFloat,
        format: @escaping (CGFloat) -> String,
        description: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            HStack {
                Slider(value: value, in: range, step: step) {
                    Text(title)
                }
                .labelsHidden()

                Text(format(value.wrappedValue))
                    .foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .trailing)
            }

            Text(description)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func dividerImageRow(title: String?, path: String?, onChoose: @escaping () -> Void, onClear: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title)
            }

            HStack {
                Button("Choose Image...", action: onChoose)

                if path != nil {
                    Button("Clear", action: onClear)
                }

                if let name = path.flatMap({ $0.isEmpty ? nil : URL(fileURLWithPath: $0).lastPathComponent }) {
                    Text(name)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    @ViewBuilder
    private var tileLayoutSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Tile Clip Shape")
                        .font(.headline)

                    Spacer()

                    Picker("Tile Clip Shape", selection: $preferences.tileClipShape) {
                        ForEach(DockClipShape.allCases) { shape in
                            Text(shape.title).tag(shape)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                Text("Choose whether Docky tile chrome keeps the current rounded corners or uses a full circle or capsule clip.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Tile Vertical Padding")
                        .font(.headline)

                    Spacer()

                    HStack {
                        Slider(value: $preferences.tileVerticalPadding, in: 8...32, step: 1) {
                            Text("Tile Vertical Padding")
                        }
                        .labelsHidden()

                        Text("\(Int(preferences.tileVerticalPadding)) pt")
                            .foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }
                }

                Text("Controls the top and bottom inset inside each dock tile.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Tile Spacing")
                        .font(.headline)

                    Spacer()

                    HStack {
                        Slider(value: $preferences.tileSpacing, in: 0...16, step: 1) {
                            Text("Tile Spacing")
                        }
                        .labelsHidden()
                        Text("\(Int(preferences.tileSpacing)) pt")
                            .foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }
                }

                Text("Controls the horizontal gap between adjacent dock tiles.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                Text("Tile Size")
                    .font(.headline)

                HStack {
                    Slider(value: systemDockTileSizeBinding, in: 16...128, step: 1) {
                        Text("Tile Size")
                    }
                    .labelsHidden()

                    Text("\(Int(dockSettings.tileSize.rounded())) pt")
                        .foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .trailing)
                }

                Text("Controls the base width and height of each dock tile.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Magnification", isOn: systemDockMagnificationBinding)
                    .font(.headline)

                Text("Allows tiles to use the enlarged dock sizing behavior when enabled.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var windowShapeSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Chrome Clip Shape")
                        .font(.headline)

                    Spacer()

                    Picker("Chrome Clip Shape", selection: $preferences.windowClipShape) {
                        ForEach(DockClipShape.allCases) { shape in
                            Text(shape.title).tag(shape)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                Text("Choose whether the dock chrome keeps the current rounded corners or uses a full circle or capsule clip.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Window Corner Radius")
                        .font(.headline)

                    Spacer()

                    HStack {
                        Slider(value: windowCornerRadiusBinding, in: 0...maximumCornerRadius, step: 1) {
                            Text("Window Corner Radius")
                        }
                        .labelsHidden()
                        Text("\(Int(min(preferences.windowCornerRadius, maximumCornerRadius))) pt")
                            .foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }
                }

                Text(windowCornerRadiusDescription)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
            .disabled(preferences.windowClipShape == .circle)
        }
    }

    @ViewBuilder
    private var windowBackgroundSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Window Background Image")
                    .font(.headline)

                HStack {
                    Button("Choose Image...") {
                        chooseWindowBackgroundImage()
                    }

                    if preferences.windowBackgroundImagePath != nil {
                        Button("Clear") {
                            preferences.windowBackgroundImagePath = nil
                        }
                    }
                }

                if let selectedWindowBackgroundImageName {
                    Text(selectedWindowBackgroundImageName)
                        .foregroundStyle(.secondary)
                }

                Text("Use an image with aspect fill behind the dock tiles. When set, it replaces the material tint and opacity until cleared.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Text("Background Image Mode")

                    Spacer()

                    Picker("Background Image Mode", selection: $preferences.windowBackgroundImageMode) {
                        ForEach(DockBackgroundImageMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .disabled(preferences.windowBackgroundImagePath == nil)
                }

                Text("Sprite mode keeps the leading and trailing thirds of the image pinned and stretches the middle along the dock's axis.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Use Custom Window Tint", isOn: usesCustomWindowTintBinding)
                    .font(.headline)

                if preferences.windowTintColor != nil {
                    ColorPicker("Window Tint", selection: windowTintBinding, supportsOpacity: false)
                }

                Text("Override the translucent tint behind the main dock window. Leave this off to keep following the system material color.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
            .disabled(usesWindowBackgroundImage)

            VStack(alignment: .leading, spacing: 8) {
                Text("Window Tint Opacity")
                    .font(.headline)

                HStack {
                    Slider(value: windowTintOpacityBinding, in: 0...1, step: 0.01) {
                        Text("Window Tint Opacity")
                    }
                    Text("\(Int(preferences.effectiveWindowTintOpacity * 100))%")
                        .foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .trailing)
                }

                Text("Controls how strongly the tint color is laid over the window blur.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
            .disabled(usesWindowBackgroundImage)
        }
    }

    private var maximumCornerRadius: CGFloat {
        (dockSettings.displayTileSize + preferences.tileVerticalPadding * 2) / 2
    }

    private var systemDockTileSizeBinding: Binding<Double> {
        Binding(
            get: { Double(dockSettings.tileSize) },
            set: { dockSettings.setTileSize(CGFloat($0)) }
        )
    }

    private var systemDockMagnificationBinding: Binding<Bool> {
        Binding(
            get: { dockSettings.magnification },
            set: { dockSettings.setMagnification($0) }
        )
    }

    private var windowCornerRadiusBinding: Binding<CGFloat> {
        Binding(
            get: { min(preferences.windowCornerRadius, maximumCornerRadius) },
            set: { preferences.windowCornerRadius = $0 }
        )
    }

    private var windowCornerRadiusDescription: String {
        switch preferences.windowClipShape {
        case .rounded:
            "Controls the roundness of the main dock window and its border, up to a full capsule."
        case .circle:
            "Circle mode uses the maximum radius automatically, so square chrome becomes circular and wider chrome becomes a capsule."
        }
    }

    private var usesCustomWindowTintBinding: Binding<Bool> {
        Binding(
            get: { preferences.windowTintColor != nil },
            set: { usesCustomTint in
                preferences.windowTintColor = usesCustomTint
                    ? (preferences.windowTintColor ?? DockColor(nsColor: preferences.effectiveWindowTintColor))
                    : nil
            }
        )
    }

    private var windowTintBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: preferences.effectiveWindowTintColor) },
            set: { newValue in
                guard let tintColor = DockColor(nsColor: NSColor(newValue)) else {
                    return
                }

                preferences.windowTintColor = tintColor
            }
        )
    }

    private var showsIndicatorColorControls: Bool {
        switch preferences.activeIndicatorShape {
        case .dot, .pill:
            true
        case .none, .image:
            false
        }
    }

    private var usesCustomActiveIndicatorColorBinding: Binding<Bool> {
        Binding(
            get: { preferences.activeIndicatorColor != nil },
            set: { usesCustomColor in
                preferences.activeIndicatorColor = usesCustomColor
                    ? (preferences.activeIndicatorColor ?? DockColor(nsColor: preferences.effectiveActiveIndicatorColor))
                    : nil
            }
        )
    }

    private var activeIndicatorColorBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: preferences.effectiveActiveIndicatorColor) },
            set: { newValue in
                guard let indicatorColor = DockColor(nsColor: NSColor(newValue)) else {
                    return
                }

                preferences.activeIndicatorColor = indicatorColor
            }
        )
    }

    private var windowTintOpacityBinding: Binding<CGFloat> {
        Binding(
            get: { preferences.effectiveWindowTintOpacity },
            set: { preferences.windowTintOpacity = min(max($0, 0), 1) }
        )
    }

    private var usesWindowBackgroundImage: Bool {
        preferences.effectiveWindowBackgroundImageURL != nil
    }

    private var selectedWindowBackgroundImageName: String? {
        guard let path = preferences.windowBackgroundImagePath, !path.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: path).lastPathComponent
    }

    private var selectedActiveIndicatorImageName: String? {
        guard let path = preferences.activeIndicatorImagePath, !path.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: path).lastPathComponent
    }

    private func chooseActiveIndicatorImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Choose Image"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        preferences.activeIndicatorImagePath = url.path
    }

    private func chooseWindowBackgroundImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Choose Image"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        preferences.windowBackgroundImagePath = url.path
    }

    private enum DividerImageSlot {
        case global, left, right
    }

    private func chooseDividerImage(slot: DividerImageSlot) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Choose Image"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        switch slot {
        case .global:
            preferences.dividerImagePath = url.path
        case .left:
            preferences.leftDividerImagePath = url.path
        case .right:
            preferences.rightDividerImagePath = url.path
        }
    }
}
