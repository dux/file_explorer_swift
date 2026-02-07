# FileExplorer

Native macOS Finder replacement built with Swift and SwiftUI. Fast, keyboard-driven, with rich file previews and iPhone file management.

[Demo page](https://dux.github.io/file_explorer_swift/web-demo/)

## Install

```
curl -fsSL https://raw.githubusercontent.com/dux/file_explorer_swift/main/install.sh?v=7e11ef4 | bash
```

![PLain](web-demo/assets/plain.png)

![File preview](web-demo/assets/file-preview.png)

![Movie info](web-demo/assets/movie.jpg)

![Install](web-demo/assets/install.png)

## Features

### File browsing
- Three-pane layout: sidebar, file browser, actions/preview
- Tree view with ancestor path breadcrumbs and indented children
- Sort by name or modified date (auto-selects per folder: Downloads/Desktop default to modified)
- Show/hide hidden files toggle
- Relative timestamps ("3 minutes", "2 hours & 15 min", "5 days")
- Compact file sizes (kb, mb, gb)
- Drag-and-drop files into folders
- Breadcrumb path navigation with clickable segments

### Sidebar
- Home directory quick access
- Pinned folders with custom emoji icons
- Mounted volumes with eject buttons
- iPhone device detection (auto-appears when connected via USB)
- Color tag filters

### File operations
- Rename (Enter key or right-pane action)
- Duplicate files
- Move to trash (Cmd+Delete)
- Create new folder / new text file
- Add to zip
- Copy file path to clipboard
- Multi-file selection with paste/move/trash batch operations
- Drag-and-drop copy between folders

### Preview pane
- **Images**: jpg, jpeg, png, gif, bmp, webp, heic, heif, tiff, tif, svg, avif, ico
- **Text/Code**: syntax highlighted for 50+ languages (Swift, Python, JS, TS, Rust, Go, C, C++, Ruby, Java, Kotlin, Scala, etc.)
- **JSON**: collapsible tree with syntax coloring
- **Markdown**: rendered HTML preview
- **Makefile**: syntax highlighted
- **PDF**: native preview with page navigation
- **Audio**: mp3, m4a, wav, aac, flac, ogg, wma, aiff, opus with waveform player and trim (ffmpeg)
- **Video**: mp4, mov, m4v, avi, mkv, webm, wmv, flv, ogv, 3gp with player and trim (ffmpeg)
- **Archives**: zip, tar, tgz, gz, bz2, xz, rar, 7z with file listing and extraction
- **DMG/ISO**: disk image contents with mount support
- **EPUB**: ebook preview with chapter navigation
- **Comics**: cbz, cbr with page-by-page reader
- **Folder gallery**: auto-detects image folders and shows thumbnail grid
- **Movie folders**: detects movie folders/files by title+year, fetches info from OMDB (poster, ratings from IMDb/RT/Metacritic, cast, plot)

### Image tools
- EXIF/metadata viewer
- Resize and crop
- Format conversion (png, jpg, webp, heic, tiff, bmp, gif, avif)

### Open-with system
- Per-file-type preferred app list
- App selector with search across all installed apps
- One-click open with any preferred app

### App management
- Uninstall .app bundles with associated data cleanup (caches, preferences, app support, containers)

### iPhone file management (via libimobiledevice USB)
- Browse iPhone app sandboxes (Documents, Library, etc.)
- Upload files from Mac to iPhone
- Download files from iPhone to Mac
- Delete files on iPhone
- Create folders on iPhone
- Multi-file selection with batch download/delete

### Search
- Fast recursive search using `fd`
- Real-time results as you type
- Navigate to result's parent folder on click

### Keyboard navigation
- Arrow keys: navigate files (up/down), enter/exit folders (left/right)
- Tab: cycle focus between sidebar, file list, and right pane
- Enter: rename selected file
- Space: toggle file selection
- Cmd+Delete: move to trash
- Cmd+A / Ctrl+A: select all
- Cmd+F: search
- Escape: cancel search / exit selection view
- Home/End: jump to first/last file
- Right pane keyboard navigation with up/down/enter

### Color tags
- 7 colors: red, orange, yellow, green, blue, purple, gray
- Assign multiple tags per file
- Browse all files by tag color from sidebar
- Tags stored in config, persist across sessions

### Folder customization
- Pin any folder to sidebar
- Assign emoji icons to pinned folders
- Emoji picker with search and category tabs
- Custom folder icons show in sidebar and file tree

### Settings (Cmd+,)
- General: font size, show preview toggle, config location
- API Keys: OMDB API key for movie info

### Custom file icons
- Catppuccin-themed SVG icons for 100+ file types
- Covers programming languages, config files, media, documents, and more
- Falls back to macOS system icons for unrecognized types

### Other
- Toast notifications for operations (copy, move, trash, errors)
- Resizable panes with drag dividers
- Persisted window layout (preview split, right pane width)
- Config stored in `~/.config/dux-file-explorer/`

## vs Finder

| Feature | Finder | FileExplorer |
|---|---|---|
| Tree view with ancestors | No | Yes |
| Keyboard-driven navigation | Limited | Full (arrows, tab cycling, right pane) |
| Color tags per file | Yes (system tags) | Yes (custom, multi-tag) |
| File preview | Quick Look (Space) | Inline preview pane, always visible |
| Code syntax highlighting | No | Yes, 50+ languages |
| JSON tree viewer | No | Yes, collapsible |
| Archive contents browsing | No (auto-extract) | Yes, browse without extracting |
| Audio/video trim | No | Yes (via ffmpeg) |
| EPUB/comic reader | No | Yes |
| Movie info from OMDB | No | Yes (poster, ratings, cast) |
| Image resize/crop/convert | No | Yes |
| EXIF viewer | Limited (Get Info) | Full metadata viewer |
| iPhone file management | Via Finder sidebar (limited) | Full sandbox browsing via USB |
| App uninstaller | Drag to trash | Finds and removes all app data |
| Custom folder emoji icons | No | Yes |
| Open-with per file type | Yes (right-click) | One-click from actions pane |
| Fast search | Spotlight (indexed) | fd-based recursive search |
| Multi-file batch operations | Yes | Yes with visual selection bar |
| Pinned folders | Sidebar favorites | Yes with custom emoji |

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
