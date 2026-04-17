//
//  DividerTileView.swift
//  Docky
//

import SwiftUI

struct DividerTileView: View {
    var body: some View {
        Rectangle()
            .fill(.primary.opacity(0.2))
            .frame(width: 1)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .contextMenu {
                Button("Settings...") {
                    (NSApp.delegate as? AppDelegate)?.showSettingsWindow(nil)
                }

                Divider()

                Button("Quit Docky") {
                    NSApp.terminate(nil)
                }
            }
    }
}
