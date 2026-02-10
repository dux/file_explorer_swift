# Code Structure - File Explorer Swift

## App Entry & Top-Level Layout

**Entry point:** `app/FileExplorerApp.swift`

- `@main struct FileExplorerApp: App` with `WindowGroup` containing `ContentView()` and a `Settings` scene with `SettingsView()`.
- `AppDelegate` handles `application(_:open:)` for files/folders opened from Finder/CLI. Posts `.openPathRequest` notification.
- CLI arguments: `args[1]` is resolved as initial path. If it is a file, the parent directory is opened and the file is selected.
- Static properties `FileExplorerApp.initialPath` and `FileExplorerApp.initialFile` carry the startup target into `FileExplorerManager.init()`.

**Window layout** (`ContentView.swift`):

```
ZStack (bottom-aligned) {
  VStack {
    Divider
    HStack {
      ShortcutsView (left sidebar)     -- width: settings.leftPaneWidth
      <draggable vertical divider>
      MainContentView                   -- minWidth: 600
    }
  }
  CustomContextMenuOverlay              -- floats above everything
  ToastView                             -- bottom notification
}
```

- `WindowAccessor` (NSViewRepresentable) saves/restores window frame via `AppSettings`.
- Minimum window: 900 x 600.

## Models

### FileExplorerManager (`Models/FileExplorerManager.swift`)
The **central @MainActor ObservableObject**. Owns all navigation, file listing, search, and selection state.

**Key published state:**
- `currentPath: URL` -- current directory
- `directories: [CachedFileInfo]`, `files: [CachedFileInfo]` -- cached contents of current dir
- `allItems: [CachedFileInfo]` -- computed `directories + files`
- `selectedItem: URL?`, `selectedIndex: Int` -- single item cursor
- `sortMode: SortMode` (.type, .name, .modified) -- triggers `loadContents()` on change
- `currentPane: MainPaneType` -- `.browser`, `.selection`, `.iphone`, `.colorTag(TagColor)`
- `browserViewMode: BrowserViewMode` -- `.files`, `.selected`
- `showHidden`, `hiddenCount`, `hasImages`
- `isSearching`, `searchQuery`, `searchResults`, `isSearchRunning`, `listCursorIndex`
- `sidebarFocused`, `sidebarIndex`, `rightPaneFocused`, `rightPaneIndex`, `rightPaneItems`
- `renamingItem`, `renameText`, `showAppSelectorForURL`

**Key methods:**
- `loadContents()` -- reads current directory via FileManager, splits into dirs/files, sorts, detects images/hidden count
- `navigateTo(_ url)` -- validates path, pushes history, sets sort default for Downloads/Desktop, loads contents, restores selection memory
- `navigateUp()` -- remembers current folder in parent's selection memory, then navigates
- `goBack()` / `goForward()` -- history-based navigation
- `openItem(_ item)` -- directories: navigate; archives: extract; files: open with preferred app
- `performSearch(_ query)` -- debounced (200ms), runs `fd` CLI tool in background, results sorted dirs-first
- `selectNext()`, `selectPrevious()`, `jumpToLetter()`, `selectFirst()`, `selectLast()` -- keyboard nav
- `addFileToSelection()`, `toggleFileSelection()`, `selectAllFiles()` -- delegates to `SelectionManager.shared`

**Private state:**
- `history: [URL]`, `historyIndex: Int` -- back/forward navigation
- `selectionMemory: [String: URL]` -- remembers selected item per directory path

### FileExplorerManagerFileOps (extension, `Models/FileExplorerManagerFileOps.swift`)
File operation methods: `createNewFolder()`, `createNewFile()`, `duplicateFile()`, `addToZip()`, `extractArchive()`, `enableUnsafeApp()`, `moveToTrash()`, `refresh()`, `startRename()`, `cancelRename()`, `confirmRename()`, `toggleHidden()`.

### FileExplorerManagerSearch (extension, `Models/FileExplorerManagerSearch.swift`)
Search methods: `startSearch()`, `cancelSearch()`, `performSearch()`, `executeSearch()`, `findFd()`. List cursor navigation: `listSelectNext()`, `listSelectPrevious()`, `listActivateItem()`.

### FileItem & SelectionManager (`Models/FileItem.swift`)
- `FileItem` -- unified file representation with `id`, `name`, `path`, `isDirectory`, `size`, `modifiedDate`, `source` (`.local` or `.iPhone`).
- `SelectionManager` -- **singleton** managing a `Set<FileItem>`. Tracks `version: Int` for change detection. Supports add/remove/toggle/clear, move/copy/delete, iPhone download/upload.

### CachedFileInfo (in FileExplorerManager.swift)
Lightweight struct: `url`, `isDirectory`, `size`, `modDate`, `isHidden`. Display model for directory listings.

### AppSettings (`Models/AppSettings.swift`)
**Singleton** persisting to `~/.config/dux-file-explorer/settings.json`. Debounced save (300ms). Key settings: font sizes, pane widths, window frame, `preferredApps`, `recentlyUsedApps`, `flatFolders`, `omdbAPIKey`.

### Other Singletons
All `@MainActor`:
- **ShortcutsManager** -- sidebar pinned folders (`~/.config/dux-file-explorer/folders.txt`)
- **ColorTagManager** -- 4-color label system (`color-labels.json`)
- **FolderIconManager** -- custom emoji folder icons (`folder-icons.json`)
- **IconProvider** -- catppuccin SVG file icons, cached
- **GitRepoManager** -- detects `.git`, parses remote URL for web links
- **NpmPackageManager** -- detects `package.json`, provides npm link
- **MovieManager** -- OMDB movie metadata + poster
- **VolumesManager** -- monitors mounted volumes via NSWorkspace notifications
- **iPhoneManager** -- iOS device detection, app listing, file browsing (`iPhoneManager.swift`), file operations (`iPhoneManagerFileOps.swift`)
- **AppSearcher** -- finds apps that can open a file type
- **AppUninstaller** -- finds leftover app data for cleanup
- **FolderSizeCache** -- cached folder size calculations (own serial queue)
- **ToastManager** -- toast notification show/dismiss
- **ContextMenuManager** -- right-click menu state

## Views Hierarchy

```
ContentView
  +-- ShortcutsView (left sidebar)
  |     +-- ShortcutRow (Home, Desktop, Downloads, Applications)
  |     +-- ColorTagBoxes
  |     +-- iPhoneRow (per device)
  |     +-- DraggableShortcutRow (pinned folders, drag-reorder)
  |     +-- VolumeRow (mounted volumes)
  |
  +-- <draggable vertical divider>
  |
  +-- MainContentView
        +-- MainPane (switches on currentPane)
        |     +-- .browser -> FileBrowserPane
        |     |     +-- SelectionBar (green, when items selected)
        |     |     +-- ActionButtonBar (hidden toggle, search, sort, new)
        |     |     +-- SearchBar + SearchResultsView (when isSearching)
        |     |     +-- FileTreeView (primary file listing)
        |     |
        |     +-- .selection -> SelectionPane
        |     +-- .iphone -> iPhoneBrowserPane
        |     +-- .colorTag(color) -> ColorTagView
        |
        +-- <draggable vertical divider>
        |
        +-- Right pane:
              +-- ActionsPane (or iPhoneActionsPane)
              +-- Preview area (when showPreviewPane):
                    MoviePreviewView / FolderGalleryPreview / PreviewPane
```

## Navigation System

### Folder navigation
- **`navigateTo(_ url)`** -- validates path, saves selection memory, pushes history, sets `currentPath`, auto-selects sort mode (.modified for Downloads/Desktop, .type otherwise), calls `loadContents()`, restores selection.
- **`navigateUp()`** -- stores current dir URL in parent's selection memory, calls `navigateTo(parent)`.
- **`goBack()` / `goForward()`** -- moves `historyIndex` through history stack.

### Breadcrumbs
- **Tree mode** (`flatFolders == false`): `FileTreeView` computes `ancestors` array from current path up to home dir (or volume mount). Each is an `AncestorRow` (clickable, indented by depth).
- **Flat mode** (`flatFolders == true`): `FlatBreadcrumbRow` -- horizontal chevron-separated path. Toggle: `Cmd+T`.

### Sidebar navigation
- Tab cycles focus: main -> right pane -> sidebar -> main.
- Arrow keys navigate sidebar items, Enter activates.

## File Display

### FileTreeView (`Views/FileTreeView.swift`)
Primary file listing. Two modes via `settings.flatFolders`:
- **Tree**: ancestor rows (indented path) + children at `ancestors.count` depth. 20pt indent per level.
- **Flat**: `FlatBreadcrumbRow` + children at depth 1.

**FileTreeRow:** icon + filename + color dots + date + size. Single click on dir: select then navigate (150ms). Click file: toggle selection. Double click: open. Drag: `NSItemProvider`. Right-click: custom context menu. Background: blue=selected, green=in selection.

### Drop handling
Both views accept `.fileURL` drops -- copies files to current directory with name deduplication.

## Preview System

`PreviewType.detect(for:)` classifies by extension/filename:
- `.image`, `.pdf`, `.text`, `.json`, `.markdown`, `.fez`, `.audio`, `.video`, `.archive`, `.comic`, `.epub`, `.dmg`, `.makefile`, `.packageJson`, `.none`

Preview views in `Views/Preview/`: TextPreviewView, SyntaxHighlightView, JSONPreviewView, MarkdownPreviewView, ImagePreviewView, PDFPreviewView, AudioPreviewView, VideoPreviewView, ArchivePreviewView, ComicPreviewView, EpubPreviewView, DMGPreviewView, MakefilePreviewView, PackageJsonPreviewView, MoviePreviewView, FolderGalleryPreview.

## Key Patterns

### State management
- Singletons with `@MainActor` for all shared managers
- `FileExplorerManager` created as `@StateObject` in ContentView, passed down via `@ObservedObject`
- Change tracking via `.version` counters (ColorTagManager, SelectionManager)

### Keyboard shortcuts (KeyCaptureView in KeyboardHandler.swift)
`NSViewRepresentable` capturing all key events. Priority: context menu -> rename -> tab cycling -> sidebar -> right pane -> search -> normal mode. Normal mode: arrows (navigate/select), Space (toggle selection), Enter (rename), Backspace (go back), Cmd+Backspace (trash), letter (jump), Cmd+T (toggle tree/flat), Cmd+F (search), Ctrl+R (refresh).

### Context menu
Custom implementation via `ContextMenuManager` + `CustomContextMenuOverlay`. Not native macOS. Supports keyboard navigation.

### Text styles
`.textStyle(.default|.buttons|.small|.title)` modifier. Font sizes configurable in AppSettings.

## File Map

```
app/
  FileExplorerApp.swift              -- @main entry, AppDelegate
  ContentView.swift                  -- Root layout, WindowAccessor
  Models/
    FileExplorerManager.swift        -- Central state manager
    FileExplorerManagerFileOps.swift  -- File operations extension
    FileExplorerManagerSearch.swift   -- Search & list cursor extension
    FileItem.swift                   -- FileItem, SelectionManager
    AppSettings.swift                -- Persisted settings singleton
    ShortcutsManager.swift           -- Sidebar pinned folders
    ColorTagManager.swift            -- Color label system
    FolderIconManager.swift          -- Custom emoji folder icons
    IconProvider.swift               -- Catppuccin SVG file icons
    GitRepoManager.swift             -- Git repo detection
    NpmPackageManager.swift          -- npm package detection
    MovieManager.swift               -- OMDB movie info
    VolumesManager.swift             -- Mounted volumes
    iPhoneManager.swift              -- iOS device detection, browsing
    iPhoneManagerFileOps.swift       -- iPhone file download/upload/delete
    AppSearcher.swift                -- App discovery for "Open with"
    AppUninstaller.swift             -- App cleanup/uninstall
    FolderSizeCache.swift            -- Cached folder size calc
    AppUpdater.swift                 -- GitHub release update checker
  Views/
    MainContentView.swift            -- Main layout, toolbar, dialogs
    KeyboardHandler.swift            -- KeyEventHandlingView, KeyCaptureView
    ShortcutsView.swift              -- Left sidebar
    ActionsPane.swift                -- Right pane actions
    iPhoneActionsPane.swift          -- iPhone-specific actions
    FileTreeView.swift               -- Tree/flat file listing (primary)
    FileTableView.swift              -- Table file listing (secondary)
    CustomContextMenu.swift          -- Right-click context menu system
    HelperViews.swift                -- FileListRow, FileDetailsView, EmptyFolderView, RenameTextField
    FileItemDialog.swift             -- File item dialog (rename, actions, details)
    SharedComponents.swift           -- Drop helpers, SheetHeader, EmptyStateView
    TextStyles.swift                 -- .textStyle() modifier system
    ToastView.swift                  -- Toast notification
    SettingsView.swift               -- Settings window
    ColorTagView.swift               -- Color tag file list
    EmojiPickerView.swift            -- Emoji picker for folder icons
    FolderGalleryPreview.swift       -- Image grid preview
    MetadataSheet.swift              -- EXIF/metadata viewer
    ImageResizeSheet.swift           -- Image resize/crop
    ImageConvertSheet.swift          -- Image format conversion
    AppSelectorSheet.swift           -- App chooser dialog
    UninstallConfirmSheet.swift      -- App uninstall confirmation
    Panes/
      MainPane.swift                 -- Pane switcher
      FileBrowserPane.swift          -- File browser with search
      SelectionPane.swift            -- Global selection view
      iPhoneBrowserPane.swift        -- iPhone file browser
    Preview/
      PreviewPane.swift              -- Preview type detection & dispatch
      TextPreviewView.swift          -- Plain text
      SyntaxHighlightView.swift      -- Syntax highlighting
      JSONPreviewView.swift          -- JSON viewer
      MarkdownPreviewView.swift      -- Markdown renderer
      FezPreviewView.swift           -- Fez template
      ImagePreviewView.swift         -- Image viewer
      PDFPreviewView.swift           -- PDF viewer
      AudioPreviewView.swift         -- Audio player
      VideoPreviewView.swift         -- Video player
      ArchivePreviewView.swift       -- Archive contents
      ComicPreviewView.swift         -- Comic reader
      EpubPreviewView.swift          -- EPUB reader
      DMGPreviewView.swift           -- DMG info
      MakefilePreviewView.swift      -- Makefile targets
      PackageJsonPreviewView.swift   -- package.json info
      MoviePreviewView.swift         -- Movie info from OMDB
```
