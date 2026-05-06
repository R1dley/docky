//
//  WindowContextActions.swift
//  Docky
//
//  Shared builder for the per-window section of context menus shown in the
//  hover preview popover and the Cmd-Tab switcher overlay. Mirrors the macOS
//  Window menu (Minimize / Zoom / Fill / Center / Move & Resize) using AX
//  geometry under the hood — no menu-walking, so this works for every app
//  that responds to AX position/size, not just Cocoa apps with a standard
//  Window menu.
//

import AppKit

@MainActor
func windowMenuContextActions(
    for window: AppWindow,
    dismiss: @escaping () -> Void
) -> [ContextAction] {
    let workspace = WorkspaceService.shared

    func run(_ action: @escaping (AppWindow) -> Bool) -> () -> Void {
        return {
            dismiss()
            _ = action(window)
        }
    }

    return [
        .action("Minimize", image: contextMenuSymbol("minus.circle"), handler: run(workspace.minimize(window:))),
        .action("Zoom", image: contextMenuSymbol("arrow.up.left.and.arrow.down.right"), handler: run(workspace.zoom(window:))),
        .action("Fill", image: contextMenuSymbol("rectangle.fill"), handler: run(workspace.fill(window:))),
        .action("Center", image: contextMenuSymbol("rectangle.center.inset.filled"), handler: run(workspace.center(window:))),
        .submenu("Move & Resize", children: [
            .action("Left", image: contextMenuSymbol("rectangle.lefthalf.filled"), handler: run(workspace.fillLeftHalf(window:))),
            .action("Right", image: contextMenuSymbol("rectangle.righthalf.filled"), handler: run(workspace.fillRightHalf(window:))),
            .action("Top", image: contextMenuSymbol("rectangle.tophalf.filled"), handler: run(workspace.fillTopHalf(window:))),
            .action("Bottom", image: contextMenuSymbol("rectangle.bottomhalf.filled"), handler: run(workspace.fillBottomHalf(window:))),
            .divider,
            .action("Top Left", image: contextMenuSymbol("arrow.up.left"), handler: run(workspace.fillTopLeftQuarter(window:))),
            .action("Top Right", image: contextMenuSymbol("arrow.up.right"), handler: run(workspace.fillTopRightQuarter(window:))),
            .action("Bottom Left", image: contextMenuSymbol("arrow.down.left"), handler: run(workspace.fillBottomLeftQuarter(window:))),
            .action("Bottom Right", image: contextMenuSymbol("arrow.down.right"), handler: run(workspace.fillBottomRightQuarter(window:))),
        ]),
    ]
}
