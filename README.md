# Docky

Docky is a Dock replacement for macOS. It reimagines the system Dock with a
configurable layout, app folders, widgets, a fullscreen Launchpad, a
Cmd-Tab-style window switcher with live previews, custom app icons, scripted
actions, and themeable appearance.

Docky is free and open source under the GNU General Public License v3.0.

## Features

- **Tiles and layout** — pin apps, folders, dividers, spacers, and widgets;
  drag to reorder.
- **App folders** — group apps, optionally showing running apps inline.
- **Widgets** — built-in widgets (weather, calendar, reminders, now playing,
  and more), plus community `.dockywidget` bundles via the widget store.
- **Launchpad** — a fullscreen app launcher with its own layout and an optional
  global shortcut.
- **Window switcher** — a global Cmd-Tab-style switcher with per-tile hover
  previews.
- **Custom app icons** — per-app icon overrides for pinned, running, and
  widget-backed apps.
- **Scripted actions** — catalog-backed AppleScript and menu-click automation.
- **Themes and profiles** — themeable appearance and switchable configuration
  profiles.

## Requirements

- macOS 14.0 or later
- Xcode 16 or later to build from source

## Building

```sh
git clone https://github.com/josejuanqm/docky.git
cd docky
open Docky.xcodeproj
```

Build and run the `Docky` scheme. Swift Package dependencies (Sparkle) resolve
automatically on first build.

Docky needs Accessibility and Screen Recording permissions to manage windows
and render previews; it prompts for these on first launch.

## App Store note

Docky uses private SkyLight / CoreGraphics Services and Accessibility SPI (see
`Docky/Private/`) to position windows, capture previews, and drive the system
Dock. Because of this, **Docky cannot be distributed on the Mac App Store** as
is. It is intended to be built from source or distributed directly.

## Dependencies

- [Sparkle](https://github.com/sparkle-project/Sparkle) — software update
  framework (BSD 3-Clause).

## License

[GNU General Public License v3.0](LICENSE). Copyright (C) 2026 Jose Quintero.
