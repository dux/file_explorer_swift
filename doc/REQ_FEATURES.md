# Requested File Explorer Features

Based on research across GitHub issues, Reddit discussions, and user feedback from popular file managers (Files, Spacedrive, nnn, yazi, ranger, superfile), here are the most requested and missing features that could be added to FileExplorer.

---

## High-Priority Features (Most Requested)

### 1. Tabs
**Status:** #1 most requested feature across all file managers
- Open multiple locations in tabs within same window
- Tab bar with close buttons and tab switching (Cmd+1-9)
- Right-click to duplicate/close/reorder tabs
- Cmd+T for new tab, Cmd+W to close

**User Pain Points:**
- Multiple windows clutter workspace
- Can't keep multiple locations accessible without losing context
- Other file explorers (Windows Explorer, Linux nautilus) have tabs

### 2. Dual-Pane / Split-Pane View
**Status:** Highly requested by power users
- Compare two folders side-by-side
- Copy/move files between panes easily
- Independent sorting and view options per pane
- Synchronized scrolling option
- Drag divider to resize panes

**User Pain Points:**
- Moving files between folders requires multiple windows or drag-drop to sidebar
- No easy way to compare folder contents
- Useful for developers comparing code versions, media organizers

### 3. Pause/Resume File Transfers
**Status:** Critical missing feature
- Show transfer progress with speed indicator
- Pause long transfers and resume later
- Better error messages with retry options
- Queue system for batch operations
- Background operations (don't block UI)

**User Pain Points:**
- Long copy operations can't be interrupted
- Network interruptions require starting over
- No indication of how long transfers will take
- Can't prioritize important transfers

### 4. Advanced Batch Rename
**Status:** Your basic rename exists, users want more
- Pattern-based renaming (regex, find & replace)
- Number sequences (file_001, file_002, file_003...)
- Insert/remove text at position
- Convert to lowercase/uppercase/title case
- Preserve/modify extensions
- Preview changes before applying

**User Pain Points:**
- Current rename is per-file only
- No way to bulk rename photos or organize files
- Common workflow for developers (rename screenshots, organize downloads)

Maybe solvable by brew app namechanger https://www.publicspace.net/app/namechanger/
Maybe solvable by brew app transnomino https://mrrsoftware.com/Transnomino/

### 5. Duplicate File Detection
**Status:** Highly requested across all platforms
- Find exact duplicates (by hash/SHA-256)
- Find near-duplicates (similar images, similar files)
- Preview duplicates side-by-side
- Delete duplicates safely (keep newest, keep largest)
- Duplicate file report

**User Pain Points:**
- Storage waste from duplicate files
- No easy way to clean up duplicates
- Manual comparison is time-consuming
- Cloud sync creates duplicates

Maybe solvable by brew app dupeguru https://dupeguru.voltaicideas.net/

---

## Medium-Priority Features

### 6. Real-Time Content Search
**Status:** Currently only filename search with `fd`
- Search inside file contents (grep-style)
- Filter by file type, size, date range, tags
- Save search queries as "smart folders" (auto-updating)
- Quick filters (images >10MB, modified today, etc.)
- Natural language search ("photos from last week")

**User Pain Points:**
- Can't find files by content
- No way to filter by multiple criteria
- Can't save useful searches

### 7. Folder Synchronization
**Status:** Unique feature, few explorers have this
- Visual diff of two folders
- Bidirectional synchronization
- Selective sync (only missing files, only newer files)
- Preview changes before applying
- Conflict resolution UI (choose which version to keep)

**User Pain Points:**
- Manual folder comparison is tedious
- No way to sync backups easily
- Developers need to sync project folders

Maybe solvable by brew app freefilesync https://freefilesync.org/

### 8. Network Drive Support
**Status:** Critical for remote work
- SFTP support with key-based auth
- FTP support
- SMB/Windows share support
- Mount remote servers as local drives
- Save connection profiles
- Upload/download with queue and progress

**User Pain Points:**
- No built-in remote file access
- Need separate apps (FileZilla, Transmit)
- Can't work with remote files seamlessly

Maybe solvable by brew app filezilla https://filezilla-project.org/
Maybe solvable by brew app cyberduck https://cyberduck.io/

### 9. Workspace / Session Saving
**Status:** Improves workflow significantly
- Save current tabs, panes, selected files
- Restore workspace on app launch
- Multiple named workspaces (e.g., "Project A", "Daily")
- Auto-save on quit
- Quick workspace switcher (Cmd+Shift+W)

**User Pain Points:**
- Lose working state on restart
- Can't save useful folder combinations
- Re-opening same folders every time is tedious

### 10. File Notes / Annotations
**Status:** Unique productivity feature
- Add sticky notes to files/folders
- Notes display in preview pane
- Search within notes
- Notes sync with tags
- Rich text formatting

**User Pain Points:**
- No way to add context to files
- "Why did I keep this file?" is common question
- Useful for collaboration and documentation

---

## Nice-to-Have Features

### 11. Keyboard Shortcut Customization
**Status:** Power user feature
- Remap all keyboard shortcuts
- Create custom shortcuts for actions
- Import/export shortcut profiles
- Multiple shortcut sets for different workflows

**User Pain Points:**
- Stuck with default shortcuts
- Some shortcuts conflict with other apps
- Vim users want hjkl navigation

### 12. Font File Preview
**Status:** Simple but useful
- Render font files directly in preview pane
- Show font metadata (family, weight, style, foundry)
- Sample text preview (user-customizable)
- Quick font comparison (select multiple fonts)

**User Pain Points:**
- Can't preview fonts without opening Font Book
- No way to quickly compare fonts
- Designers need faster font browsing

Maybe solvable by built-in Font Book (open with: open -a Font Book /path/to/font.ttf)

### 13. Recent Files Quick Access
**Status:** Workflow accelerator
- Global Cmd+E to show recent files panel
- Filter by type (images, code, documents)
- Pinned recent items
- Time-based filters (today, this week, this month)
- Open from any location

**User Pain Points:**
- Can't quickly access recent files from different folders
- Finder's recent files are buried
- No filtering by file type

### 14. Smart Folders / Auto-Collections
**Status:** Dynamic organization
- "Recent Screenshots" (location + modified + name contains "screenshot")
- "Large Downloads" (Downloads folder + >100MB)
- "Code Snippets" (files with extensions: swift, rs, go, py, js, ts)
- "Documents from Last Week" (doc types + date filter)
- Auto-update based on criteria
- Create custom smart folders with query builder

**User Pain Points:**
- Manual folder organization is time-consuming
- Files get lost in deep folder structures
- Need to remember where files are

### 15. File Conflict Resolution UI
**Status:** Better handling of duplicates
- Compare files (diff view for text)
- Show metadata (size, date, type)
- Keep both (auto-rename: file_1.ext, file_2.ext)
- Skip/overwrite options per file during batch operations
- Preview before action

**User Pain Points:**
- Batch operations fail on conflicts
- Can't see which file to keep
- Manual resolution is tedious

Maybe solvable by built-in FileMerge (included with Xcode CLT, open with: opendiff file1 file2)

---

## Unique Opportunity Features (Differentiators)

### 16. AI-Powered Features
**Status:** Modern touch, sets you apart
- Automatic file categorization (images, code, documents, media, etc.)
- Smart tagging based on content (faces in photos, code language detection)
- Natural language search ("photos from last week with mountains")
- Suggest related files based on content analysis
- Organize folders automatically

**User Pain Points:**
- Manual organization is time-consuming
- Finding related files is hard
- No intelligent file management

### 17. Version History for Local Files
**Status:** Like Time Machine but per-file
- Show file modification history
- Revert to previous versions
- Compare versions side-by-side
- Space-efficient storage (only changed blocks)
- Time-stamped snapshots

**User Pain Points:**
- Accidental deletions or overwrites are permanent
- No way to see file evolution
- Need to restore from backups for single file changes

### 18. Advanced Archive Management
**Status:** Expand existing archive support
- Browse inside nested archives (zip inside zip)
- Extract specific files from archives without full extraction
- Split/join large archives
- Create archives with custom compression (zip, 7z, rar, tar.gz)
- Archive password protection

**User Pain Points:**
- Full extraction is slow and uses disk space
- No way to preview archives before extracting
- Limited archive format support

Maybe solvable by brew app keka https://www.keka.io/

### 19. Clipboard History for File Paths
**Status:** Productivity booster
- Remember last 20 file paths copied
- Quick paste menu (Cmd+Shift+V)
- Path format options (full path, ~ shorthand, relative)
- Share files via path sharing
- Paste as markdown links

**User Pain Points:**
- Lose file paths when copying new content
- Need to manually type paths in terminal/editor
- No quick way to share file locations

Maybe solvable by brew app maccy https://maccy.app/

### 20. Integration Extensions / Plugins
**Status:** Extensibility
- Plugins for cloud providers (Dropbox, Google Drive, OneDrive)
- Git-enhanced operations (diff staging, commit preview)
- Terminal command runner in selected directory
- Custom actions per file type
- Python/AppleScript automation hooks

**User Pain Points:**
- App is closed, can't extend functionality
- Can't integrate with existing workflows
- Developers want to automate tasks

---

## Technical Improvements

### 21. Async Background Operations
**Status:** Performance optimization
- Large file operations don't block UI
- Progress notifications (center stage, dock badge)
- Cancel/undo operations
- Queue system for batch operations
- Non-blocking search and indexing

**User Pain Points:**
- UI freezes during large operations
- Can't cancel long-running tasks
- No visibility into background processes

### 22. Custom Columns in File List
**Status:** Better information density
- Add/remove metadata columns (width, height, duration, bitrate, etc.)
- Reorder columns by dragging
- Auto-size columns (fit content)
- Save column layout per folder type
- Column filters (show/hide specific values)

**User Pain Points:**
- Can't see file metadata without selecting file
- Columns are fixed and not customizable
- No way to see specific info (video duration, image dimensions)

### 23. Theme System
**Status:** Appearance customization
- Dark/light/auto themes
- Custom accent colors
- Multiple color schemes (Catppuccin, Dracula, Nord, Gruvbox)
- Export/import themes
- Per-folder themes

**User Pain Points:**
- Appearance is fixed
- Users want dark mode (already have, but not customizable)
- Can't match system theme or personal preference

---

## Feature Comparison: FileExplorer vs Competitors

| Feature | FileExplorer | Finder | Windows Explorer | Files.app | Spacedrive |
|---------|--------------|--------|------------------|-----------|------------|
| Tabs | ❌ | ✅ | ✅ | ✅ | ✅ |
| Dual-Pane | ❌ | ❌ | ❌ | ❌ | ❌ |
| Pause/Resume Transfer | ❌ | ❌ | ❌ | ❌ | ❌ |
| Advanced Batch Rename | ⚠️ Basic | ❌ | ❌ | ❌ | ⚠️ Basic |
| Duplicate Detection | ❌ | ❌ | ❌ | ❌ | ❌ |
| Content Search | ⚠️ Filename only | ✅ Spotlight | ✅ | ⚠️ Filename | ⚠️ Filename |
| Folder Sync | ❌ | ❌ | ❌ | ❌ | ❌ |
| Network Drives (SFTP) | ❌ | ⚠️ Connect | ⚠️ Map | ❌ | ❌ |
| Workspaces | ❌ | ❌ | ❌ | ❌ | ❌ |
| File Notes | ❌ | ❌ | ❌ | ❌ | ❌ |
| Keyboard Customization | ❌ | ❌ | ❌ | ❌ | ❌ |
| Font Preview | ❌ | ⚠️ Quick Look | ⚠️ Preview | ❌ | ❌ |
| Recent Files Quick Access | ❌ | ⚠️ Sidebar | ✅ | ❌ | ❌ |
| Smart Folders | ❌ | ✅ | ✅ | ✅ | ❌ |
| Conflict Resolution UI | ⚠️ Basic | ⚠️ | ⚠️ | ⚠️ | ⚠️ |
| iPhone USB File Management | ✅ | ✅ | ❌ | ❌ | ❌ |
| Movie Info Lookup | ✅ | ❌ | ❌ | ❌ | ❌ |
| Git Integration | ✅ | ❌ | ❌ | ❌ | ❌ |
| NPM Detection | ✅ | ❌ | ❌ | ❌ | ❌ |
| Code Preview (50+ langs) | ✅ | ❌ | ❌ | ❌ | ❌ |
| Archive Browsing | ✅ | ❌ | ❌ | ❌ | ❌ |
| Color Tags | ✅ | ✅ | ❌ | ✅ | ❌ |
| App Uninstaller | ✅ | ❌ | ❌ | ❌ | ❌ |

**Legend:** ✅ = Has feature, ⚠️ = Partial/basic support, ❌ = Missing

---

## Recommended Implementation Priority

Based on user demand, implementation complexity, and differentiation value:

### Phase 1 (Quick Wins, High Impact)
1. **Tabs** - High demand, moderate complexity, major UX improvement
2. **Pause/Resume Transfers** - Critical functionality, moderate complexity
3. **File Notes** - Simple, unique feature, high differentiation
4. **Custom Columns** - Moderate complexity, significant usability improvement

### Phase 2 (Differentiators)
5. **Dual-Pane View** - High demand from power users, good differentiator
6. **Duplicate Detection** - High value, unique feature
7. **Folder Sync** - Complex but highly valuable, few competitors
8. **Content Search** - Major limitation currently, complex but doable

### Phase 3 (Polish & Power Users)
9. **Advanced Batch Rename** - Expands existing feature
10. **Workspaces** - Moderate complexity, workflow improvement
11. **Keyboard Customization** - Power user feature, good differentiator
12. **Smart Folders** - Complex but powerful, matches Finder capabilities

### Phase 4 (Advanced Features)
13. **Network Drive Support** - High complexity, high value
14. **Version History** - Very complex, unique feature
15. **AI Features** - Complex, modern differentiator
16. **Plugin System** - Most complex, highest flexibility

---

## What Makes FileExplorer Stand Out Already

✅ iPhone file management via USB (unique)
✅ Movie info lookup (OMDB + IMDB scraping)
✅ Git repo auto-detection
✅ NPM package detection
✅ Rich preview (50+ languages, audio/video trim, EPUB/comics)
✅ Folder emoji icons
✅ Color tags with sidebar browsing
✅ App uninstaller with data cleanup
✅ Enable unsigned apps one-click
✅ Archive browsing without extraction
✅ Multi-file selection with visual bar

These unique features already differentiate FileExplorer from competitors. Adding the high-priority features above would make it a compelling replacement for Finder for most users.

---

## Additional Research Sources

- GitHub Issues: Files (#1928, #7518, #9991, #1396, #17831, #17956, #17953, #8385, #9377, #5845, #17878, #17876)
- GitHub Issues: Spacedrive (#2993, #2968, #2924, #2953, #3017, #3008)
- GitHub Issues: yazi (#2665, #1707, #2556, #2385, #3521, #140, #631, #3252)
- GitHub Issues: ranger (#738, #539, #1890, #2075, #1173, #902, #2062, #1194, #456)
- Reddit: r/osx, r/macapps, r/software, r/AskReddit
- Hacker News: File manager discussions
- StackOverflow: File explorer limitations questions

**Research Date:** February 2026

