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
    @Published var duplicatingItem: URL? = nil
    @Published var duplicateText: String = ""
    @Published var currentPane: MainPaneType = .browser
    @Published var hiddenCount: Int = 0
    @Published var hasImages: Bool = false
    @Published var showItemDialog: Bool = false
    @Published var showNewFolderDialog: Bool = false
    @Published var newFolderName: String = "New Folder"
    @Published var newFolderTargetURL: URL? = nil
    @Published var showNewFileDialog: Bool = false
    @Published var newFileName: String = "untitled.txt"
    @Published var newFileTargetURL: URL? = nil
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
    @Published var searchScannedCount: Int = 0
    @Published var searchExtensionCounts: [String: Int] = [:]
    @Published var selectedSearchExtension: String? = nil
    internal var searchIndexTask: Task<Void, Never>?
    internal var searchToken: Int = 0
    internal var searchAllItems: [CachedFileInfo] = []

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

    // Use unified SelectionManager
    var selection: SelectionManager { SelectionManager.shared }

    private var history: [URL] = []
    private var historyIndex: Int = -1

    // Directory monitor: detects external changes to current folder
    private var directoryMonitorSource: DispatchSourceFileSystemObject?
    private var monitorDebounceTask: Task<Void, Never>?

    let fileManager = FileManager.default

    var allItems: [CachedFileInfo] {
        directories + files
    }

    private static let lastFolderFile = AppSettings.configBase.appendingPathComponent("last-folder.txt")

    private func saveLastFolder(_ url: URL) {
        try? url.path.write(to: Self.lastFolderFile, atomically: true, encoding: .utf8)
    }

    private static func loadLastFolder() -> URL? {
        guard let path = try? String(contentsOf: lastFolderFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else { return nil }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return nil }
        return URL(fileURLWithPath: path)
    }

    init() {
        // Use initial path from command line argument if provided
        if let initialPath = FileExplorerApp.initialPath {
            self.currentPath = initialPath
        } else if let lastFolder = Self.loadLastFolder() {
            self.currentPath = lastFolder
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
        startMonitoringDirectory()

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
            // Navigate to parent, then select the file once its listing is in
            let parent = url.deletingLastPathComponent()
            navigateTo(parent) { [weak self] in
                guard let self else { return }
                self.selectedItem = url
                if let index = self.allItems.firstIndex(where: { $0.url.path == url.path }) {
                    self.selectedIndex = index
                }
            }
        }

        // Bring window to front
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private var loadGeneration = 0

    struct DirectoryListing: Sendable {
        let directories: [CachedFileInfo]
        let files: [CachedFileInfo]
        let hiddenCount: Int
        let hasImages: Bool
    }

    enum DirectoryLoadResult: Sendable {
        case success(DirectoryListing)
        case failure(String)
    }

    /// Directories with at most this many entries load synchronously so ordinary
    /// navigation swaps atomically (no flash of the previous folder). It's a heuristic:
    /// small folders never freeze the UI, and this many local `stat`s stays well under
    /// a frame. Larger folders enumerate off the main thread instead.
    private static let syncLoadThreshold = 1000

    /// Loads the current directory. Small directories enumerate synchronously; large
    /// ones do the read, per-file stat, and sort off the main thread and publish on
    /// main. `completion` runs on main once results are in (used to restore or select
    /// an item). A generation token discards stale async loads so rapid navigation
    /// only ever shows the newest folder.
    func loadContents(completion: (() -> Void)? = nil) {
        loadGeneration &+= 1
        let generation = loadGeneration
        let path = currentPath
        let mode = sortMode
        // For Trash folder, show all files including hidden
        let isTrash = path.lastPathComponent == ".Trash"
        let showAll = showHidden || isTrash

        // Fast path: enumerating a small directory is instant, so do it inline - the
        // listing swaps in the same update with no flicker of the previous folder.
        // The name-only count is one cheap directory read (no per-file stats).
        let entryCount = (try? fileManager.contentsOfDirectory(atPath: path.path).count) ?? 0
        if entryCount <= Self.syncLoadThreshold {
            applyLoadResult(Self.enumerateDirectory(at: path, showAll: showAll, isTrash: isTrash, sortMode: mode))
            completion?()
            return
        }

        // Slow path: large directories enumerate off the main thread. The outer Task
        // inherits this method's main-actor isolation, so `completion` never crosses
        // actors; only the enumeration hops off the main thread.
        Task { [weak self] in
            let outcome = await Task.detached(priority: .userInitiated) {
                Self.enumerateDirectory(at: path, showAll: showAll, isTrash: isTrash, sortMode: mode)
            }.value
            guard let self, self.loadGeneration == generation else { return }
            self.applyLoadResult(outcome)
            completion?()
        }
    }

    private func applyLoadResult(_ result: DirectoryLoadResult) {
        switch result {
        case .success(let listing):
            directories = listing.directories
            files = listing.files
            hiddenCount = listing.hiddenCount
            hasImages = listing.hasImages
            selectedIndex = -1
            selectedItem = nil
        case .failure(let message):
            ToastManager.shared.showError("Error loading directory: \(message)")
            directories = []
            files = []
        }
    }

    /// Directory read + per-file stat + sort. Runs off the main actor; returns a
    /// message on failure so the result stays Sendable.
    nonisolated private static func enumerateDirectory(at path: URL, showAll: Bool, isTrash: Bool, sortMode: SortMode) -> DirectoryLoadResult {
        let fm = FileManager.default
        let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey, .isHiddenKey]
        do {
            var contents = try fm.contentsOfDirectory(at: path, includingPropertiesForKeys: Array(resourceKeys), options: [])

            // Fallback for Trash: TCC may silently return empty, use /bin/ls
            if isTrash && contents.isEmpty {
                contents = listViaProcess(path)
            }

            var dirs: [CachedFileInfo] = []
            var fils: [CachedFileInfo] = []
            var hiddenSkipped = 0

            for url in contents {
                let values = try? url.resourceValues(forKeys: resourceKeys)
                let hidden = url.lastPathComponent.hasPrefix(".") || (values?.isHidden ?? false)
                if !showAll && hidden {
                    hiddenSkipped += 1
                    continue
                }

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

            let hasImages = fils.contains { FileExtensions.images.contains($0.url.pathExtension.lowercased()) }
            return .success(DirectoryListing(
                directories: sortItems(dirs, sortMode: sortMode),
                files: sortItems(fils, sortMode: sortMode),
                hiddenCount: hiddenSkipped,
                hasImages: hasImages
            ))
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    /// Fallback directory listing using /bin/ls for TCC-protected folders
    nonisolated private static func listViaProcess(_ dir: URL) -> [URL] {
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

    nonisolated private static func sortItems(_ items: [CachedFileInfo], sortMode: SortMode) -> [CachedFileInfo] {
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
        return .name
    }

    private func saveSelection() {
        if let item = selectedItem {
            selectionMemory[currentPath.path] = item
        }
    }

    func restoreSelection() {
        if let remembered = selectionMemory[currentPath.path],
           let index = allItems.firstIndex(where: { $0.url == remembered }) {
            selectedIndex = index
            selectedItem = remembered
        } else {
            selectedIndex = -1
            selectedItem = nil
        }
    }

    /// Navigate to a folder. Once the (async) listing is in, `onLoaded` runs on main;
    /// when nil it restores the remembered selection. Callers that want a specific
    /// post-navigation selection pass their own closure instead of racing the load.
    func navigateTo(_ url: URL, onLoaded: (() -> Void)? = nil) {
        let targetURL = url.standardizedFileURL
        var isDirectory: ObjCBool = false

        guard fileManager.fileExists(atPath: targetURL.path, isDirectory: &isDirectory) else {
            print("Path does not exist: \(targetURL.path)")
            return
        }

        if isDirectory.boolValue {
            if isSearching {
                cancelSearch()
            }
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
            loadContents { [weak self] in
                if let onLoaded { onLoaded() } else { self?.restoreSelection() }
            }
            saveLastFolder(targetURL)
            startMonitoringDirectory()
        } else {
            selectedItem = targetURL
            if let index = allItems.firstIndex(where: { $0.url == targetURL }) {
                selectedIndex = index
            }
        }
    }

    /// Navigate into a folder and select the folder itself (no child highlighted).
    /// Used by sidebar/breadcrumb/volume taps that shouldn't restore a child selection.
    func navigateToFolder(_ url: URL) {
        navigateTo(url) { [weak self] in self?.selectCurrentFolder() }
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
        var next = sidebarIndex + 1
        while next < items.count && ShortcutsManager.isDivider(items[next]) {
            next += 1
        }
        if next < items.count {
            sidebarIndex = next
        }
    }

    func sidebarSelectPrevious() {
        let items = sidebarItems
        var prev = sidebarIndex - 1
        while prev >= 0 && ShortcutsManager.isDivider(items[prev]) {
            prev -= 1
        }
        if prev >= 0 {
            sidebarIndex = prev
        }
    }

    func sidebarActivate() {
        let items = sidebarItems
        guard sidebarIndex >= 0 && sidebarIndex < items.count else { return }
        let url = items[sidebarIndex]
        if currentPane == .iphone {
            iPhoneManager.shared.currentDevice = nil
            currentPane = .browser
        }
        navigateToFolder(url)
    }

    func focusSidebar() {
        sidebarFocused = true
        let items = sidebarItems
        if let idx = items.firstIndex(where: { $0.path == currentPath.path }) {
            sidebarIndex = idx
        } else if sidebarIndex < 0 || sidebarIndex >= items.count {
            sidebarIndex = min(sidebarIndex, max(items.count - 1, 0))
        }
    }

    func unfocusSidebar() {
        sidebarFocused = false
    }

    // MARK: - Right pane navigation

    func focusRightPane() {
        rightPaneFocused = true
        if let idx = rightPaneItems.firstIndex(where: { $0.id == "selectapp" }) {
            rightPaneIndex = idx
        } else {
            rightPaneIndex = 0
        }
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
        loadContents { [weak self] in self?.restoreSelection() }
        startMonitoringDirectory()
    }

    var canGoBack: Bool {
        historyIndex > 0
    }

    var canGoForward: Bool {
        historyIndex < history.count - 1
    }

    // MARK: - Directory monitoring

    func startMonitoringDirectory() {
        stopMonitoringDirectory()

        let path = currentPath.path
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.delete, .rename, .write],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = source.data
            Task { @MainActor in
                if flags.contains(.delete) || flags.contains(.rename) {
                    self.handleCurrentDirectoryDeleted()
                } else if flags.contains(.write) {
                    self.debounceReloadContents()
                }
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        directoryMonitorSource = source
        source.resume()
    }

    private func stopMonitoringDirectory() {
        directoryMonitorSource?.cancel()
        directoryMonitorSource = nil
        monitorDebounceTask?.cancel()
        monitorDebounceTask = nil
    }

    private func handleCurrentDirectoryDeleted() {
        stopMonitoringDirectory()
        // Walk up to the nearest existing ancestor
        var parent = currentPath.deletingLastPathComponent()
        while !fileManager.fileExists(atPath: parent.path) && parent.path != "/" {
            parent = parent.deletingLastPathComponent()
        }
        navigateToFolder(parent)
    }

    private func debounceReloadContents() {
        monitorDebounceTask?.cancel()
        monitorDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
            guard !Task.isCancelled else { return }
            self.loadContents()
        }
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
            selectedItem = allItems[selectedIndex].url
        } else {
            selectedIndex = -1
            selectedItem = currentPath
        }
    }

    func selectPrevious() {
        guard !allItems.isEmpty else { return }
        if selectedIndex > 0 {
            selectedIndex -= 1
            selectedItem = allItems[selectedIndex].url
        } else if selectedIndex == 0 {
            selectedIndex = -1
            selectedItem = currentPath
        } else {
            selectedIndex = allItems.count - 1
            selectedItem = allItems[selectedIndex].url
        }
    }

    func openSelected() {
        guard let item = selectedItem else { return }
        openItem(item)
    }

    private static let archiveExtensions = FileExtensions.archives

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

    // Shift+click: add the contiguous range between the cursor and the clicked row
    func selectRange(to index: Int) {
        guard let target = allItems[safe: index] else { return }
        let anchor = (selectedIndex >= 0 && selectedIndex < allItems.count) ? selectedIndex : index
        let urls = (min(anchor, index)...max(anchor, index)).compactMap { allItems[safe: $0]?.url }
        let added = selection.addLocals(urls)
        if added > 0 {
            ToastManager.shared.show("Added to selection (\(selection.count) item\(selection.count == 1 ? "" : "s"))")
        }
        selectItem(at: index, url: target.url)
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

}
