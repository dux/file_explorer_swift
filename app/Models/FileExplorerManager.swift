import SwiftUI
import AppKit

enum MainPaneType: Equatable {
    case browser
    case selection
    case iphone
    case colorTag(TagColor)
}

enum BrowserViewMode: String, CaseIterable {
    case files = "Files"
    case selected = "Selected"
}

enum SortMode: String, CaseIterable {
    case type = "Type"
    case name = "Name"
    case modified = "Modified"
}

struct RightPaneItem: Identifiable {
    let id: String
    let title: String
    let action: @MainActor () -> Void
}

struct CachedFileInfo: Identifiable, Equatable {
    let url: URL
    let isDirectory: Bool
    let size: Int64
    let modDate: Date?
    let isHidden: Bool

    var id: String { url.absoluteString }
    var name: String { url.lastPathComponent }
}

@MainActor
class FileExplorerManager: ObservableObject {
    @Published var currentPath: URL
    @Published var directories: [CachedFileInfo] = []
    @Published var files: [CachedFileInfo] = []
    @Published var selectedItem: URL?
    @Published var selectedIndex: Int = -1
    @Published var showHidden: Bool = false
    @Published var renamingItem: URL? = nil
    @Published var renameText: String = ""
    @Published var currentPane: MainPaneType = .browser
    @Published var hiddenCount: Int = 0
    @Published var hasImages: Bool = false
    @Published var showItemDialog: Bool = false
    @Published var showAppSelectorForURL: URL? = nil

    // Sidebar focus
    @Published var sidebarFocused: Bool = false
    @Published var sidebarIndex: Int = 0

    // Right pane focus
    @Published var rightPaneFocused: Bool = false
    @Published var rightPaneIndex: Int = 0
    @Published var rightPaneItems: [RightPaneItem] = []

    // Search state
    @Published var isSearching: Bool = false
    @Published var searchQuery: String = ""
    @Published var searchResults: [CachedFileInfo] = []
    @Published var isSearchRunning: Bool = false
    @Published var listCursorIndex: Int = -1
    private var searchTask: Process?
    private var searchDebounceTask: Task<Void, Never>?

    // Remember selected item per folder
    private var selectionMemory: [String: URL] = [:]
    @Published var browserViewMode: BrowserViewMode = .files {
        didSet {
            AppSettings.shared.browserViewMode = browserViewMode.rawValue.lowercased()
        }
    }
    private var suppressSortDidSet = false
    @Published var sortMode: SortMode = .type {
        didSet {
            if !suppressSortDidSet {
                loadContents()
            }
        }
    }

    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "bmp", "webp", "heic", "heif", "tiff", "tif", "svg", "avif"]

    // Use unified SelectionManager
    var selection: SelectionManager { SelectionManager.shared }

    private var history: [URL] = []
    private var historyIndex: Int = -1

    let fileManager = FileManager.default

    var allItems: [CachedFileInfo] {
        directories + files
    }

    init() {
        // Use initial path from command line argument if provided
        if let initialPath = FileExplorerApp.initialPath {
            self.currentPath = initialPath
        } else {
            self.currentPath = fileManager.homeDirectoryForCurrentUser
        }
        // Restore browser view mode from settings
        let savedMode = AppSettings.shared.browserViewMode.lowercased()
        if let mode = BrowserViewMode.allCases.first(where: { $0.rawValue.lowercased() == savedMode }) {
            self.browserViewMode = mode
        }
        loadContents()
        history.append(currentPath)
        historyIndex = 0

        // If a file was passed, select it
        if let initialFile = FileExplorerApp.initialFile {
            selectedItem = initialFile
            if let index = allItems.firstIndex(where: { $0.url.path == initialFile.path }) {
                selectedIndex = index
            }
            FileExplorerApp.initialFile = nil
        }

        // Listen for open requests (when app is already running)
        NotificationCenter.default.addObserver(
            forName: .openPathRequest,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self, let url = notification.object as? URL else { return }
            Task { @MainActor in
                self.handleOpenRequest(url)
            }
        }
    }

    func handleOpenRequest(_ url: URL) {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }

        if isDirectory.boolValue {
            navigateTo(url)
        } else {
            // Navigate to parent, then select the file
            let parent = url.deletingLastPathComponent()
            navigateTo(parent)
            selectedItem = url
            if let index = allItems.firstIndex(where: { $0.url.path == url.path }) {
                selectedIndex = index
            }
        }

        // Bring window to front
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func loadContents() {
        do {
            let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey]

            // For Trash folder, show all files including hidden
            let isTrash = currentPath.lastPathComponent == ".Trash"
            let showAll = showHidden || isTrash

            var contents = try fileManager.contentsOfDirectory(at: currentPath, includingPropertiesForKeys: Array(resourceKeys), options: [])

            // Fallback for Trash: TCC may silently return empty, use /bin/ls
            if isTrash && contents.isEmpty {
                contents = listViaProcess(currentPath)
            }

            var dirs: [CachedFileInfo] = []
            var fils: [CachedFileInfo] = []
            var hiddenSkipped = 0

            for url in contents {
                let hidden = url.lastPathComponent.hasPrefix(".")
                if !showAll && hidden {
                    hiddenSkipped += 1
                    continue
                }

                let values = try? url.resourceValues(forKeys: resourceKeys)
                let isDir = values?.isDirectory ?? false
                let size = Int64(values?.fileSize ?? 0)
                let modDate = values?.contentModificationDate

                let info = CachedFileInfo(url: url, isDirectory: isDir, size: size, modDate: modDate, isHidden: hidden)

                if isDir {
                    dirs.append(info)
                } else {
                    fils.append(info)
                }
            }

            directories = sortItems(dirs)
            files = sortItems(fils)
            hiddenCount = hiddenSkipped
            hasImages = fils.contains { Self.imageExtensions.contains($0.url.pathExtension.lowercased()) }

            selectedIndex = -1
            selectedItem = nil

        } catch {
            ToastManager.shared.showError("Error loading directory: \(error.localizedDescription)")
            directories = []
            files = []
        }
    }

    /// Fallback directory listing using /bin/ls for TCC-protected folders
    nonisolated private func listViaProcess(_ dir: URL) -> [URL] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ls")
        process.arguments = ["-1A", dir.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let output = String(data: data, encoding: .utf8) else { return [] }
            return output.split(separator: "\n").compactMap { name in
                let n = String(name)
                guard !n.isEmpty else { return nil }
                return dir.appendingPathComponent(n)
            }
        } catch {
            return []
        }
    }

    private func sortItems(_ items: [CachedFileInfo]) -> [CachedFileInfo] {
        switch sortMode {
        case .name:
            return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .modified:
            return items.sorted { a, b in
                let d1 = a.modDate ?? Date.distantPast
                let d2 = b.modDate ?? Date.distantPast
                return d1 > d2
            }
        case .type:
            return items.sorted { a, b in
                let ext1 = a.url.pathExtension.lowercased()
                let ext2 = b.url.pathExtension.lowercased()
                
                let hasExt1 = !ext1.isEmpty
                let hasExt2 = !ext2.isEmpty
                
                if hasExt1 != hasExt2 {
                    return hasExt1
                }
                
                if ext1 != ext2 {
                    return ext1.localizedStandardCompare(ext2) == .orderedAscending
                }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        }
    }

    private func defaultSortMode(for path: URL) -> SortMode {
        let home = fileManager.homeDirectoryForCurrentUser
        let downloads = home.appendingPathComponent("Downloads")
        let desktop = home.appendingPathComponent("Desktop")

        if path.path == downloads.path || path.path == desktop.path {
            return .modified
        }
        return .type
    }

    private func saveSelection() {
        if let item = selectedItem {
            selectionMemory[currentPath.path] = item
        }
    }

    private func restoreSelection() {
        if let remembered = selectionMemory[currentPath.path],
           let index = allItems.firstIndex(where: { $0.url == remembered }) {
            selectedIndex = index
            selectedItem = remembered
        } else {
            selectedIndex = -1
            selectedItem = nil
        }
    }

    func navigateTo(_ url: URL) {
        let targetURL = url.standardizedFileURL
        var isDirectory: ObjCBool = false

        guard fileManager.fileExists(atPath: targetURL.path, isDirectory: &isDirectory) else {
            print("Path does not exist: \(targetURL.path)")
            return
        }

        if isDirectory.boolValue {
            saveSelection()

            // Add to history only if different from current
            if currentPath.path != targetURL.path {
                if historyIndex < history.count - 1 {
                    history.removeLast(history.count - historyIndex - 1)
                }
                history.append(targetURL)
                historyIndex = history.count - 1
            }

            currentPath = targetURL
            suppressSortDidSet = true
            sortMode = defaultSortMode(for: targetURL)
            suppressSortDidSet = false
            loadContents()
            restoreSelection()
        } else {
            selectedItem = targetURL
            if let index = allItems.firstIndex(where: { $0.url == targetURL }) {
                selectedIndex = index
            }
        }
    }

    func navigateUp() {
        guard currentPath.path != "/" else { return }
        let child = currentPath
        let parent = currentPath.deletingLastPathComponent()
        // Remember the folder we came from so it gets selected in the parent
        selectionMemory[parent.path] = child
        navigateTo(parent)
    }

    // MARK: - Sidebar navigation

    var sidebarItems: [URL] {
        let sm = ShortcutsManager.shared
        let builtIn = sm.allShortcuts.filter { $0.isBuiltIn }.map(\.url)
        let custom = sm.customFolders
        let volumes = VolumesManager.shared.volumes.map(\.url)
        return builtIn + custom + volumes
    }

    func sidebarSelectNext() {
        let items = sidebarItems
        guard !items.isEmpty else { return }
        sidebarIndex = min(sidebarIndex + 1, items.count - 1)
    }

    func sidebarSelectPrevious() {
        sidebarIndex = max(sidebarIndex - 1, 0)
    }

    func sidebarActivate() {
        let items = sidebarItems
        guard sidebarIndex >= 0 && sidebarIndex < items.count else { return }
        let url = items[sidebarIndex]
        if currentPane == .iphone {
            iPhoneManager.shared.currentDevice = nil
            currentPane = .browser
        }
        navigateTo(url)
        selectCurrentFolder()
    }

    func focusSidebar() {
        sidebarFocused = true
        // Clamp sidebar index to valid range.
        let items = sidebarItems
        if sidebarIndex < 0 || sidebarIndex >= items.count {
            if let idx = items.firstIndex(where: { $0.path == currentPath.path }) {
                sidebarIndex = idx
            } else {
                sidebarIndex = min(sidebarIndex, max(items.count - 1, 0))
            }
        }
    }

    func unfocusSidebar() {
        sidebarFocused = false
    }

    // MARK: - Right pane navigation

    func focusRightPane() {
        rightPaneFocused = true
        rightPaneIndex = 0
    }

    func unfocusRightPane() {
        rightPaneFocused = false
    }

    func rightPaneSelectNext() {
        guard !rightPaneItems.isEmpty else { return }
        rightPaneIndex = min(rightPaneIndex + 1, rightPaneItems.count - 1)
    }

    func rightPaneSelectPrevious() {
        rightPaneIndex = max(rightPaneIndex - 1, 0)
    }

    func rightPaneActivate() {
        guard rightPaneIndex >= 0 && rightPaneIndex < rightPaneItems.count else { return }
        rightPaneItems[rightPaneIndex].action()
    }

    func goBack() {
        guard historyIndex > 0 else { return }
        navigateHistory(to: historyIndex - 1)
    }

    func goForward() {
        guard historyIndex < history.count - 1 else { return }
        navigateHistory(to: historyIndex + 1)
    }

    private func navigateHistory(to index: Int) {
        saveSelection()
        historyIndex = index
        currentPath = history[index]
        loadContents()
        restoreSelection()
    }

    var canGoBack: Bool {
        historyIndex > 0
    }

    var canGoForward: Bool {
        historyIndex < history.count - 1
    }

    // MARK: - Selection (Single item only)

    func selectItem(at index: Int, url: URL) {
        selectedIndex = index
        selectedItem = url
    }

    // MARK: - Keyboard Navigation

    func selectNext() {
        guard !allItems.isEmpty else { return }
        if selectedIndex < allItems.count - 1 {
            selectedIndex += 1
        } else {
            selectedIndex = 0
        }
        selectedItem = allItems[selectedIndex].url
    }

    func selectPrevious() {
        guard !allItems.isEmpty else { return }
        if selectedIndex > 0 {
            selectedIndex -= 1
        } else {
            selectedIndex = allItems.count - 1
        }
        selectedItem = allItems[selectedIndex].url
    }

    func openSelected() {
        guard let item = selectedItem else { return }
        openItem(item)
    }

    private static let archiveExtensions: Set<String> = ["zip", "tar", "tgz", "gz", "bz2", "xz", "rar", "7z"]

    func openItem(_ item: URL) {
        var isDirectory: ObjCBool = false
        fileManager.fileExists(atPath: item.path, isDirectory: &isDirectory)

        if isDirectory.boolValue {
            navigateTo(item)
        } else {
            let ext = item.pathExtension.lowercased()
            if Self.archiveExtensions.contains(ext) {
                extractArchive(item)
            } else {
                openFileWithPreferredApp(item)
            }
        }
    }

    func openFileWithPreferredApp(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        let fileType = ext.isEmpty ? "__empty__" : ext
        let apps = AppSettings.shared.getPreferredApps(for: fileType)
        if let firstPath = apps.first,
           FileManager.default.fileExists(atPath: firstPath) {
            let appURL = URL(fileURLWithPath: firstPath)
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
            AppSettings.shared.addRecentlyUsedApp(appPath: firstPath)
        } else {
            showAppSelectorForURL = url
        }
    }

    func extractArchive(_ url: URL) {
        let parentDir = url.deletingLastPathComponent()
        let baseName = url.deletingPathExtension().lastPathComponent
        var destName = baseName
        var counter = 1
        var destURL = parentDir.appendingPathComponent(destName)

        // Find unique folder name
        while fileManager.fileExists(atPath: destURL.path) {
            destName = "\(baseName)-\(counter)"
            destURL = parentDir.appendingPathComponent(destName)
            counter += 1
        }

        let ext = url.pathExtension.lowercased()
        let srcPath = url.path
        let destPath = destURL.path
        let finalDestName = destName

        ToastManager.shared.show("Extracting...")

        Task.detached {
            // Create destination folder
            do {
                try FileManager.default.createDirectory(atPath: destPath, withIntermediateDirectories: true)
            } catch {
                await MainActor.run {
                    ToastManager.shared.show("Error creating folder: \(error.localizedDescription)")
                }
                return
            }

            let process = Process()
            let errPipe = Pipe()
            process.standardError = errPipe
            process.standardOutput = Pipe() // discard stdout

            switch ext {
            case "zip":
                process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                process.arguments = ["-o", srcPath, "-d", destPath]
            case "tar", "tgz", "gz", "bz2", "xz":
                process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
                process.arguments = ["-xf", srcPath, "-C", destPath]
            case "rar":
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["unrar", "x", "-o+", srcPath, destPath + "/"]
            case "7z":
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["7z", "x", srcPath, "-o" + destPath, "-y"]
            default:
                process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                process.arguments = ["-o", srcPath, "-d", destPath]
            }

            do {
                try process.run()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                let status = process.terminationStatus
                await MainActor.run {
                    if status == 0 {
                        self.loadContents()
                        ToastManager.shared.show("Extracted to \(finalDestName)/")
                    } else {
                        let errMsg = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown error"
                        // Clean up empty folder on failure
                        try? FileManager.default.removeItem(atPath: destPath)
                        ToastManager.shared.show("Extract failed: \(errMsg)")
                    }
                }
            } catch {
                await MainActor.run {
                    try? FileManager.default.removeItem(atPath: destPath)
                    ToastManager.shared.show("Extract failed: \(error.localizedDescription)")
                }
            }
        }
    }

    func jumpToLetter(_ letter: Character) {
        let lower = String(letter).lowercased()
        let startFrom = selectedIndex + 1
        // Search from after current selection, then wrap around
        let afterCurrent = allItems[startFrom...].firstIndex(where: { $0.url.lastPathComponent.lowercased().hasPrefix(lower) })
        let wrapped = afterCurrent ?? allItems[..<startFrom].firstIndex(where: { $0.url.lastPathComponent.lowercased().hasPrefix(lower) })
        if let index = wrapped {
            selectedIndex = index
            selectedItem = allItems[index].url
        } else {
            ToastManager.shared.show("No item starting with '\(letter.uppercased())'")
        }
    }

    func selectFirst() {
        guard !allItems.isEmpty else { return }
        selectedIndex = 0
        selectedItem = allItems[0].url
    }

    func selectLast() {
        guard !allItems.isEmpty else { return }
        selectedIndex = allItems.count - 1
        selectedItem = allItems[selectedIndex].url
    }

    func toggleShowHidden() {
        showHidden.toggle()
        loadContents()
    }

    // Add a file to global selection
    func addFileToSelection(_ url: URL) {
        selection.addLocal(url)
    }

    // Toggle a file in global selection
    func toggleFileSelection(_ url: URL) {
        if let item = FileItem.fromLocal(url) {
            selection.toggle(item)
        }
    }

    // Select all files in current folder
    func selectAllFiles() {
        for file in files {
            selection.addLocal(file.url)
        }
    }

    // Add current selection to global selection
    func addToGlobalSelection() {
        if let item = selectedItem {
            addFileToSelection(item)
        }
    }

    // Remove from global selection
    func removeFromGlobalSelection(_ url: URL) {
        if let item = FileItem.fromLocal(url) {
            selection.remove(item)
        }
    }

    // Toggle current selection in global selection
    func toggleGlobalSelection() {
        if let item = selectedItem, let fileItem = FileItem.fromLocal(item) {
            selection.toggle(fileItem)
        }
    }

    // Clear global selection
    func clearGlobalSelection() {
        selection.clear()
    }

    // Check if URL is in selection
    func isInSelection(_ url: URL) -> Bool {
        selection.containsLocal(url)
    }

    // MARK: - Search with fd

    private static func findFd() -> String? {
        for dir in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"] {
            let path = "\(dir)/fd"
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        return nil
    }

    func startSearch() {
        isSearching = true
        searchQuery = ""
        searchResults = []
        listCursorIndex = -1
    }

    func cancelSearch() {
        searchTask?.terminate()
        searchTask = nil
        isSearching = false
        searchQuery = ""
        searchResults = []
        isSearchRunning = false
        listCursorIndex = -1
    }

    // MARK: - List cursor navigation (search results / color tags)

    func listSelectNext(count: Int) {
        guard count > 0 else { return }
        if listCursorIndex < count - 1 {
            listCursorIndex += 1
        } else {
            listCursorIndex = 0
        }
    }

    func listSelectPrevious(count: Int) {
        guard count > 0 else { return }
        if listCursorIndex > 0 {
            listCursorIndex -= 1
        } else {
            listCursorIndex = count - 1
        }
    }

    func listActivateItem(url: URL, isDirectory: Bool) {
        if isDirectory {
            if isSearching { cancelSearch() }
            currentPane = .browser
            navigateTo(url)
        } else {
            openFileWithPreferredApp(url)
        }
    }

    func performSearch(_ query: String) {
        searchQuery = query

        // Cancel previous search
        searchDebounceTask?.cancel()
        searchTask?.terminate()
        searchTask = nil

        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            searchResults = []
            isSearchRunning = false
            return
        }

        guard let fdPath = Self.findFd() else {
            ToastManager.shared.show("fd not found — install with: brew install fd")
            return
        }

        isSearchRunning = true

        searchDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms debounce
            guard !Task.isCancelled else { return }
            self.executeSearch(query: query, trimmed: trimmed, fdPath: fdPath)
        }
    }

    private func executeSearch(query: String, trimmed: String, fdPath: String) {
        let searchDir = currentPath.path
        let showAll = showHidden

        let process = Process()
        process.executableURL = URL(fileURLWithPath: fdPath)
        var args = ["--max-results", "200", "--color", "never"]
        if showAll {
            args += ["--hidden", "--no-ignore"]
        }
        args += [trimmed, searchDir]
        process.arguments = args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        self.searchTask = process

        Task.detached {
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                guard process.terminationStatus == 0 || process.terminationStatus == 1,
                      let output = String(data: data, encoding: .utf8) else {
                    await MainActor.run { [weak self] in
                        self?.searchResults = []
                        self?.isSearchRunning = false
                    }
                    return
                }

                let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey]
                let results: [CachedFileInfo] = output.split(separator: "\n").compactMap { line in
                    let path = String(line)
                    guard !path.isEmpty else { return nil }
                    let url = URL(fileURLWithPath: path)
                    let values = try? url.resourceValues(forKeys: resourceKeys)
                    let isDir = values?.isDirectory ?? false
                    let size = Int64(values?.fileSize ?? 0)
                    let modDate = values?.contentModificationDate
                    let hidden = url.lastPathComponent.hasPrefix(".")
                    return CachedFileInfo(url: url, isDirectory: isDir, size: size, modDate: modDate, isHidden: hidden)
                }

                // Sort: directories first, then by name
                let sorted = results.sorted { a, b in
                    if a.isDirectory != b.isDirectory { return a.isDirectory }
                    return a.name.localizedStandardCompare(b.name) == .orderedAscending
                }

                await MainActor.run { [weak self] in
                    // Only update if query still matches
                    if self?.searchQuery == query {
                        self?.searchResults = sorted
                        self?.isSearchRunning = false
                    }
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.searchResults = []
                    self?.isSearchRunning = false
                }
            }
        }
    }
}
