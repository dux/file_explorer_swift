# FileExplorer

Native macOS Finder replacement built with Swift and SwiftUI.

## Features

- Three-pane layout: sidebar, file browser, preview/actions
- File previews: images, text, code, JSON, markdown, PDF, audio, video, archives, DMG, EPUB, comics
- iPhone file browsing via libimobiledevice (USB)
- Keyboard-driven navigation (arrows, tab cycling, shortcuts)
- Fast search using `fd`
- Color tags, pinned folders, mounted volumes with eject
- Custom Catppuccin file type icons
- Open-with system with per-type preferred apps

## Requirements

- macOS 13+
- `libimobiledevice` (`brew install libimobiledevice`)
- Optional: `fd` (search), `ffmpeg` (audio/video trimming)

## Build

```
make          # build, install to ~/Applications, and run
make build    # build and install only
make clean    # remove build artifacts
```

## Config

Settings stored in `~/.config/dux-file-explorer/`.
