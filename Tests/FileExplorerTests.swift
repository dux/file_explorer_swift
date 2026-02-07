// swiftlint:disable file_length
import Testing
import Foundation
@testable import FileExplorer

// MARK: - CachedFileInfo Tests

@Suite("CachedFileInfo")
struct CachedFileInfoTests {
    @Test("id is derived from URL")
    func idFromURL() {
        let url = URL(fileURLWithPath: "/tmp/test.txt")
        let info = CachedFileInfo(url: url, isDirectory: false, size: 100, modDate: nil, isHidden: false)
        #expect(info.id == url.absoluteString)
    }

    @Test("name is last path component")
    func nameFromURL() {
        let info = CachedFileInfo(url: URL(fileURLWithPath: "/Users/test/Documents/file.txt"), isDirectory: false, size: 0, modDate: nil, isHidden: false)
        #expect(info.name == "file.txt")
    }

    @Test("allItems combines directories and files")
    @MainActor func allItemsCombined() {
        let manager = FileExplorerManager()
        let dir = CachedFileInfo(url: URL(fileURLWithPath: "/tmp/a"), isDirectory: true, size: 0, modDate: nil, isHidden: false)
        let file = CachedFileInfo(url: URL(fileURLWithPath: "/tmp/b.txt"), isDirectory: false, size: 10, modDate: nil, isHidden: false)
        manager.directories = [dir]
        manager.files = [file]
        #expect(manager.allItems.count == 2)
        #expect(manager.allItems[0].isDirectory == true)
        #expect(manager.allItems[1].isDirectory == false)
    }
}

// MARK: - Enum Tests

@Suite("Enums")
struct EnumTests {
    @Test("SortMode raw values")
    func sortModeRawValues() {
        #expect(SortMode.name.rawValue == "Name")
        #expect(SortMode.modified.rawValue == "Modified")
    }

    @Test("BrowserViewMode raw values")
    func browserViewModeRawValues() {
        #expect(BrowserViewMode.files.rawValue == "Files")
        #expect(BrowserViewMode.selected.rawValue == "Selected")
    }

    @Test("MainPaneType equality")
    func mainPaneTypeEquality() {
        let browser1 = MainPaneType.browser
        let browser2 = MainPaneType.browser
        let iphone1 = MainPaneType.iphone
        let iphone2 = MainPaneType.iphone
        #expect(browser1 == browser2)
        #expect(iphone1 == iphone2)
        let tagRed1 = MainPaneType.colorTag(.red)
        let tagRed2 = MainPaneType.colorTag(.red)
        #expect(tagRed1 == tagRed2)
        #expect(tagRed1 != MainPaneType.colorTag(.blue))
        #expect(browser1 != MainPaneType.selection)
    }

    @Test("TagColor has all four cases")
    func tagColorCases() {
        #expect(TagColor.allCases.count == 4)
        #expect(TagColor.allCases.contains(.red))
        #expect(TagColor.allCases.contains(.blue))
        #expect(TagColor.allCases.contains(.green))
        #expect(TagColor.allCases.contains(.orange))
    }

    @Test("TagColor labels are capitalized")
    func tagColorLabels() {
        #expect(TagColor.red.label == "Red")
        #expect(TagColor.blue.label == "Blue")
        #expect(TagColor.green.label == "Green")
        #expect(TagColor.orange.label == "Orange")
    }

    @Test("TagColor raw values")
    func tagColorRawValues() {
        #expect(TagColor.red.rawValue == "red")
        #expect(TagColor(rawValue: "blue") == .blue)
        #expect(TagColor(rawValue: "invalid") == nil)
    }
}

// MARK: - TaggedFile Tests

@Suite("TaggedFile")
struct TaggedFileTests {
    @Test("parentPath shortens home directory to tilde")
    func parentPathHome() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let file = TaggedFile(url: home.appendingPathComponent("test.txt"), exists: true, isDirectory: false)
        #expect(file.parentPath == "~")
    }

    @Test("parentPath shortens subdirectory of home")
    func parentPathSubdir() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let file = TaggedFile(url: home.appendingPathComponent("Documents/test.txt"), exists: true, isDirectory: false)
        #expect(file.parentPath == "~/Documents")
    }

    @Test("parentPath keeps absolute path for non-home")
    func parentPathAbsolute() {
        let file = TaggedFile(url: URL(fileURLWithPath: "/tmp/test.txt"), exists: true, isDirectory: false)
        #expect(file.parentPath == "/tmp")
    }

    @Test("name is last path component")
    func nameProperty() {
        let file = TaggedFile(url: URL(fileURLWithPath: "/tmp/myfile.pdf"), exists: true, isDirectory: false)
        #expect(file.name == "myfile.pdf")
    }

    @Test("id is path")
    func idProperty() {
        let file = TaggedFile(url: URL(fileURLWithPath: "/tmp/test.txt"), exists: true, isDirectory: false)
        #expect(file.id == "/tmp/test.txt")
    }
}

// MARK: - Test Helpers

func makeLocalItem(_ name: String, path: String) -> FileItem {
    FileItem(id: path, name: name, path: path, isDirectory: false, size: 0, modifiedDate: nil, source: .local)
}

func makeIPhoneItem(_ name: String, path: String) -> FileItem {
    FileItem(id: "iphone:dev1:app1:\(path)", name: name, path: path, isDirectory: false, size: 0, modifiedDate: nil, source: .iPhone(deviceId: "dev1", appId: "app1", appName: "App"))
}

// MARK: - FileItem Tests

@Suite("FileItem")
struct FileItemTests {
    @Test("fromLocal creates correct item")
    func fromLocal() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let item = FileItem.fromLocal(home)
        #expect(item != nil)
        #expect(item?.name == home.lastPathComponent)
        if case .local = item?.source {} else {
            Issue.record("Expected .local source")
        }
    }

    @Test("items are equal by id")
    func equality() {
        let a = makeLocalItem("test.txt", path: "/tmp/test.txt")
        let b = makeLocalItem("test.txt", path: "/tmp/test.txt")
        #expect(a == b)
    }

    @Test("different paths are not equal")
    func inequality() {
        let a = makeLocalItem("a.txt", path: "/tmp/a.txt")
        let b = makeLocalItem("b.txt", path: "/tmp/b.txt")
        #expect(a != b)
    }

    @Test("localURL returns URL for local items")
    func localURL() {
        let item = makeLocalItem("f.txt", path: "/tmp/f.txt")
        #expect(item.localURL?.path == "/tmp/f.txt")
    }

    @Test("localURL returns nil for iPhone items")
    func localURLNilForIPhone() {
        let item = makeIPhoneItem("f.txt", path: "/Documents/f.txt")
        #expect(item.localURL == nil)
    }

    @Test("displayPath shortens home directory")
    func displayPathLocal() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let item = makeLocalItem("test.txt", path: "\(home)/Documents/test.txt")
        #expect(item.displayPath == "~/Documents/test.txt")
    }

    @Test("displayPath shows iPhone prefix")
    func displayPathIPhone() {
        let item = makeIPhoneItem("f.txt", path: "/Documents/f.txt")
        #expect(item.displayPath == "iPhone: App/Documents/f.txt")
    }
}

// MARK: - SelectionManager Tests

@Suite("SelectionManager")
struct SelectionManagerTests {
    @Test("add and remove items")
    @MainActor func addRemove() {
        let sel = SelectionManager.shared
        sel.clear()
        let item = makeLocalItem("test.txt", path: "/tmp/test-sel.txt")
        sel.add(item)
        #expect(sel.count == 1)
        #expect(sel.contains(item))
        sel.remove(item)
        #expect(sel.isEmpty)
        #expect(!sel.contains(item))
    }

    @Test("clear removes all items")
    @MainActor func clearAll() {
        let sel = SelectionManager.shared
        sel.clear()
        sel.add(makeLocalItem("a", path: "/tmp/a"))
        sel.add(makeLocalItem("b", path: "/tmp/b"))
        #expect(sel.count == 2)
        sel.clear()
        #expect(sel.isEmpty)
    }

    @Test("toggle adds then removes")
    @MainActor func toggle() {
        let sel = SelectionManager.shared
        sel.clear()
        let item = makeLocalItem("t", path: "/tmp/toggle-test")
        sel.toggle(item)
        #expect(sel.contains(item))
        sel.toggle(item)
        #expect(!sel.contains(item))
    }

    @Test("duplicate add does not increase count")
    @MainActor func duplicateAdd() {
        let sel = SelectionManager.shared
        sel.clear()
        let item = makeLocalItem("dup", path: "/tmp/dup-test")
        sel.add(item)
        sel.add(item)
        #expect(sel.count == 1)
    }

    @Test("localItems filters correctly")
    @MainActor func localItemsFilter() {
        let sel = SelectionManager.shared
        sel.clear()
        sel.add(makeLocalItem("local", path: "/tmp/local"))
        sel.add(makeIPhoneItem("phone", path: "/phone/file"))
        #expect(sel.localItems.count == 1)
        #expect(sel.iPhoneItems.count == 1)
        sel.clear()
    }

    @Test("removeByPath removes matching item")
    @MainActor func removeByPath() {
        let sel = SelectionManager.shared
        sel.clear()
        sel.add(makeLocalItem("x", path: "/tmp/x"))
        sel.removeByPath("/tmp/x")
        #expect(sel.isEmpty)
    }
}

// MARK: - FileExplorerManager Navigation Tests

@Suite("FileExplorerManager Navigation")
struct NavigationTests {
    @Test("navigateTo changes currentPath")
    @MainActor func navigateToDirectory() {
        let manager = FileExplorerManager()
        let target = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        manager.navigateTo(target)
        #expect(manager.currentPath.path == target.standardizedFileURL.path)
    }

    @Test("navigateUp goes to parent")
    @MainActor func navigateUp() {
        let manager = FileExplorerManager()
        let home = FileManager.default.homeDirectoryForCurrentUser
        let target = home.appendingPathComponent("Desktop")
        manager.navigateTo(target)
        manager.navigateUp()
        #expect(manager.currentPath.path == home.standardizedFileURL.path)
    }

    @Test("clearSelection resets selected state")
    @MainActor func clearSelection() {
        let manager = FileExplorerManager()
        manager.selectedIndex = 5
        manager.selectedItem = URL(fileURLWithPath: "/tmp/test")
        manager.clearSelection()
        #expect(manager.selectedIndex == -1)
        #expect(manager.selectedItem == nil)
    }

    @Test("selectCurrentFolder selects the current path")
    @MainActor func selectCurrentFolder() {
        let manager = FileExplorerManager()
        let target = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        manager.navigateTo(target)
        manager.selectCurrentFolder()
        #expect(manager.selectedIndex == -1)
        #expect(manager.selectedItem == manager.currentPath)
    }

    @Test("sidebar focus and unfocus")
    @MainActor func sidebarFocus() {
        let manager = FileExplorerManager()
        #expect(!manager.sidebarFocused)
        manager.focusSidebar()
        #expect(manager.sidebarFocused)
        manager.unfocusSidebar()
        #expect(!manager.sidebarFocused)
    }

    @Test("right pane focus and unfocus")
    @MainActor func rightPaneFocus() {
        let manager = FileExplorerManager()
        #expect(!manager.rightPaneFocused)
        manager.focusRightPane()
        #expect(manager.rightPaneFocused)
        #expect(manager.rightPaneIndex == 0)
        manager.unfocusRightPane()
        #expect(!manager.rightPaneFocused)
    }
}

// MARK: - ToastManager Tests

@Suite("ToastManager")
struct ToastManagerTests {
    @Test("show sets message and isShowing")
    @MainActor func showMessage() {
        let toast = ToastManager.shared
        toast.show("Test message")
        #expect(toast.message == "Test message")
        #expect(toast.isShowing)
        #expect(toast.style == .info)
    }

    @Test("showError sets error style")
    @MainActor func showError() {
        let toast = ToastManager.shared
        toast.showError("Error occurred")
        #expect(toast.message == "Error occurred")
        #expect(toast.isShowing)
        #expect(toast.style == .error)
    }
}

// MARK: - FolderSizeCache Tests

@Suite("FolderSizeCache")
struct FolderSizeCacheTests {
    @Test("cache returns nil for unknown path")
    func unknownPath() {
        let cache = FolderSizeCache.shared
        let fake = URL(fileURLWithPath: "/tmp/nonexistent-folder-\(UUID().uuidString)")
        #expect(cache.getCachedSize(for: fake) == nil)
    }

    @Test("set and get cached size for existing directory")
    func setAndGet() {
        let cache = FolderSizeCache.shared
        // Use a unique temp dir so no stale cache entries interfere
        let testDir = FileManager.default.temporaryDirectory.appendingPathComponent("cache-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testDir) }
        cache.setCachedSize(for: testDir, size: 12345)
        // Give the async barrier write time to complete
        Thread.sleep(forTimeInterval: 0.15)
        let size = cache.getCachedSize(for: testDir)
        #expect(size == 12345)
    }

    @Test("invalidate removes cached entry")
    func invalidate() {
        let cache = FolderSizeCache.shared
        let testDir = FileManager.default.temporaryDirectory.appendingPathComponent("cache-inv-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testDir) }
        cache.setCachedSize(for: testDir, size: 999)
        Thread.sleep(forTimeInterval: 0.15)
        cache.invalidate(for: testDir)
        Thread.sleep(forTimeInterval: 0.15)
        let size = cache.getCachedSize(for: testDir)
        #expect(size == nil)
    }
}

// MARK: - AppUninstaller Tests

@Suite("AppUninstaller")
struct AppUninstallerTests {
    @Test("returns empty for nonexistent app")
    func nonexistentApp() {
        let paths = AppUninstaller.findAppData(for: URL(fileURLWithPath: "/tmp/FakeApp-\(UUID().uuidString).app"))
        #expect(paths.isEmpty)
    }

    @Test("finds data for real app with known bundle ID")
    func realApp() {
        // Safari is always installed and has data
        let safari = URL(fileURLWithPath: "/Applications/Safari.app")
        let paths = AppUninstaller.findAppData(for: safari)
        // Safari should have at least some data dirs (Caches, Preferences, etc.)
        #expect(!paths.isEmpty)
    }
}

// MARK: - Helper Function Tests

@Suite("Helpers")
struct HelperTests {
    @Test("formatPath shortens home to tilde")
    func formatPathHome() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(formatPath(home, full: true) == "~")
    }

    @Test("formatPath shortens subdirectory")
    func formatPathSubdir() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = home + "/Documents"
        #expect(formatPath(path, full: true) == "~/Documents")
    }

    @Test("formatPath returns last component when not full")
    func formatPathShort() {
        #expect(formatPath("/Users/test/Documents", full: false) == "Documents")
    }

    @Test("formatPath keeps absolute for non-home paths")
    func formatPathAbsolute() {
        #expect(formatPath("/tmp/test", full: true) == "/tmp/test")
    }
}

// MARK: - SuppressSortDidSet Tests

@Suite("NavigateTo SortMode")
struct NavigateToSortModeTests {
    @Test("navigating to Downloads sets sortMode to modified")
    @MainActor func downloadsUsesModifiedSort() {
        let manager = FileExplorerManager()
        let downloads = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        manager.navigateTo(downloads)
        #expect(manager.sortMode == .modified)
    }

    @Test("navigating to Documents keeps sortMode as name")
    @MainActor func documentsUsesNameSort() {
        let manager = FileExplorerManager()
        let docs = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
        manager.navigateTo(docs)
        #expect(manager.sortMode == .name)
    }

    @Test("navigating from Downloads to Documents changes sortMode back to name")
    @MainActor func sortModeChangesOnNavigation() {
        let manager = FileExplorerManager()
        let downloads = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        let docs = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
        manager.navigateTo(downloads)
        #expect(manager.sortMode == .modified)
        manager.navigateTo(docs)
        #expect(manager.sortMode == .name)
    }
}

// MARK: - UniqueDestination (via copyLocalItems) Tests

@Suite("UniqueDestination")
struct UniqueDestinationTests {
    @Test("copyLocalItems creates numbered copy when name conflicts")
    @MainActor func copyWithConflict() throws {
        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory.appendingPathComponent("unique-dest-\(UUID().uuidString)")
        try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmpDir) }

        // Create source file
        let srcDir = tmpDir.appendingPathComponent("src")
        try fm.createDirectory(at: srcDir, withIntermediateDirectories: true)
        let srcFile = srcDir.appendingPathComponent("file.txt")
        try "original".write(to: srcFile, atomically: true, encoding: .utf8)

        // Create conflicting file in destination
        let destDir = tmpDir.appendingPathComponent("dest")
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        let conflicting = destDir.appendingPathComponent("file.txt")
        try "existing".write(to: conflicting, atomically: true, encoding: .utf8)

        // Add source file to selection and copy
        let sel = SelectionManager.shared
        sel.clear()
        sel.addLocal(srcFile)
        let count = sel.copyLocalItems(to: destDir)
        #expect(count == 1)

        // The copy should be named "file 2.txt"
        let copied = destDir.appendingPathComponent("file 2.txt")
        #expect(fm.fileExists(atPath: copied.path))

        // Original conflicting file should still be there
        #expect(try String(contentsOf: conflicting, encoding: .utf8) == "existing")
        #expect(try String(contentsOf: copied, encoding: .utf8) == "original")

        sel.clear()
    }

    @Test("copyLocalItems uses original name when no conflict")
    @MainActor func copyNoConflict() throws {
        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory.appendingPathComponent("unique-dest-nc-\(UUID().uuidString)")
        try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmpDir) }

        let srcDir = tmpDir.appendingPathComponent("src")
        try fm.createDirectory(at: srcDir, withIntermediateDirectories: true)
        let srcFile = srcDir.appendingPathComponent("noconflict.txt")
        try "data".write(to: srcFile, atomically: true, encoding: .utf8)

        let destDir = tmpDir.appendingPathComponent("dest")
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)

        let sel = SelectionManager.shared
        sel.clear()
        sel.addLocal(srcFile)
        let count = sel.copyLocalItems(to: destDir)
        #expect(count == 1)

        let copied = destDir.appendingPathComponent("noconflict.txt")
        #expect(fm.fileExists(atPath: copied.path))

        sel.clear()
    }

    @Test("copyLocalItems handles multiple conflicts with incrementing numbers")
    @MainActor func copyMultipleConflicts() throws {
        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory.appendingPathComponent("unique-dest-mc-\(UUID().uuidString)")
        try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmpDir) }

        let srcDir = tmpDir.appendingPathComponent("src")
        try fm.createDirectory(at: srcDir, withIntermediateDirectories: true)
        let srcFile = srcDir.appendingPathComponent("doc.pdf")
        try "pdf-data".write(to: srcFile, atomically: true, encoding: .utf8)

        let destDir = tmpDir.appendingPathComponent("dest")
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        // Create "doc.pdf" and "doc 2.pdf" already in dest
        try "v1".write(to: destDir.appendingPathComponent("doc.pdf"), atomically: true, encoding: .utf8)
        try "v2".write(to: destDir.appendingPathComponent("doc 2.pdf"), atomically: true, encoding: .utf8)

        let sel = SelectionManager.shared
        sel.clear()
        sel.addLocal(srcFile)
        let count = sel.copyLocalItems(to: destDir)
        #expect(count == 1)

        // Should get "doc 3.pdf"
        let copied = destDir.appendingPathComponent("doc 3.pdf")
        #expect(fm.fileExists(atPath: copied.path))

        sel.clear()
    }
}

// MARK: - ShortcutItem Stable ID Tests

@Suite("ShortcutItem")
struct ShortcutItemTests {
    @Test("id is derived from URL path")
    func idFromPath() {
        let item = ShortcutItem(url: URL(fileURLWithPath: "/Users/test/Desktop"), name: "Desktop", isBuiltIn: true)
        #expect(item.id == "/Users/test/Desktop")
    }

    @Test("same URL produces same id")
    func stableId() {
        let url = URL(fileURLWithPath: "/Applications")
        let a = ShortcutItem(url: url, name: "Apps", isBuiltIn: true)
        let b = ShortcutItem(url: url, name: "Applications", isBuiltIn: false)
        #expect(a.id == b.id)
    }

    @Test("different URLs produce different ids")
    func differentIds() {
        let a = ShortcutItem(url: URL(fileURLWithPath: "/tmp/a"), name: "A", isBuiltIn: false)
        let b = ShortcutItem(url: URL(fileURLWithPath: "/tmp/b"), name: "B", isBuiltIn: false)
        #expect(a.id != b.id)
    }
}

// MARK: - ContainsLocal Tests

@Suite("SelectionManager ContainsLocal")
struct ContainsLocalTests {
    @Test("containsLocal returns true for added local URL")
    @MainActor func containsLocalTrue() {
        let sel = SelectionManager.shared
        sel.clear()
        let item = makeLocalItem("test.txt", path: "/tmp/contains-local-test")
        sel.add(item)
        #expect(sel.containsLocal(URL(fileURLWithPath: "/tmp/contains-local-test")))
        sel.clear()
    }

    @Test("containsLocal returns false for non-existent URL")
    @MainActor func containsLocalFalse() {
        let sel = SelectionManager.shared
        sel.clear()
        #expect(!sel.containsLocal(URL(fileURLWithPath: "/tmp/not-added")))
    }

    @Test("containsLocal returns false for iPhone items with same path")
    @MainActor func containsLocalNotIPhone() {
        let sel = SelectionManager.shared
        sel.clear()
        let item = makeIPhoneItem("phone.txt", path: "/tmp/phone-path")
        sel.add(item)
        #expect(!sel.containsLocal(URL(fileURLWithPath: "/tmp/phone-path")))
        sel.clear()
    }
}

// MARK: - ColorTagManager Tests

@Suite("ColorTagManager")
struct ColorTagManagerTests {
    @MainActor private func makeTempManager() -> (ColorTagManager, URL) {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("color-tag-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let jsonPath = tmpDir.appendingPathComponent("color-labels.json")
        let mgr = ColorTagManager(filePath: jsonPath)
        return (mgr, tmpDir)
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    @Test("add and count are consistent")
    @MainActor func addAndCount() {
        let (mgr, dir) = makeTempManager()
        defer { cleanup(dir) }

        let url1 = URL(fileURLWithPath: "/tmp/file1.txt")
        let url2 = URL(fileURLWithPath: "/tmp/file2.txt")

        mgr.add(url1, color: .red)
        mgr.add(url2, color: .red)

        #expect(mgr.count(for: .red) == 2)
        #expect(mgr.list(.red).count == 2)
    }

    @Test("count matches list count always")
    @MainActor func countMatchesList() {
        let (mgr, dir) = makeTempManager()
        defer { cleanup(dir) }

        let urls = (1...5).map { URL(fileURLWithPath: "/tmp/test-\($0).txt") }
        for url in urls {
            mgr.add(url, color: .blue)
        }

        #expect(mgr.count(for: .blue) == mgr.list(.blue).count)
        #expect(mgr.count(for: .blue) == 5)

        mgr.remove(urls[0], color: .blue)
        #expect(mgr.count(for: .blue) == mgr.list(.blue).count)
        #expect(mgr.count(for: .blue) == 4)

        mgr.remove(urls[1], color: .blue)
        mgr.remove(urls[2], color: .blue)
        #expect(mgr.count(for: .blue) == mgr.list(.blue).count)
        #expect(mgr.count(for: .blue) == 2)
    }

    @Test("duplicate add does not increase count")
    @MainActor func duplicateAdd() {
        let (mgr, dir) = makeTempManager()
        defer { cleanup(dir) }

        let url = URL(fileURLWithPath: "/tmp/dup.txt")
        mgr.add(url, color: .green)
        mgr.add(url, color: .green)
        mgr.add(url, color: .green)

        #expect(mgr.count(for: .green) == 1)
        #expect(mgr.list(.green).count == 1)
    }

    @Test("remove reduces count")
    @MainActor func removeReducesCount() {
        let (mgr, dir) = makeTempManager()
        defer { cleanup(dir) }

        let url = URL(fileURLWithPath: "/tmp/rm.txt")
        mgr.add(url, color: .orange)
        #expect(mgr.count(for: .orange) == 1)

        mgr.remove(url, color: .orange)
        #expect(mgr.count(for: .orange) == 0)
        #expect(mgr.list(.orange).isEmpty)
    }

    @Test("remove all colors")
    @MainActor func removeAllColors() {
        let (mgr, dir) = makeTempManager()
        defer { cleanup(dir) }

        let url = URL(fileURLWithPath: "/tmp/multi.txt")
        mgr.add(url, color: .red)
        mgr.add(url, color: .blue)
        mgr.add(url, color: .green)

        #expect(mgr.colorsForFile(url).count == 3)

        mgr.remove(url)
        for color in TagColor.allCases {
            #expect(mgr.count(for: color) == 0)
            #expect(mgr.list(color).isEmpty)
        }
    }

    @Test("toggle adds then removes")
    @MainActor func toggleAddRemove() {
        let (mgr, dir) = makeTempManager()
        defer { cleanup(dir) }

        let url = URL(fileURLWithPath: "/tmp/toggle.txt")
        mgr.toggle(url, color: .red)
        #expect(mgr.count(for: .red) == 1)
        #expect(mgr.isTagged(url, color: .red))

        mgr.toggle(url, color: .red)
        #expect(mgr.count(for: .red) == 0)
        #expect(!mgr.isTagged(url, color: .red))
    }

    @Test("totalCount is sum of all colors")
    @MainActor func totalCountSum() {
        let (mgr, dir) = makeTempManager()
        defer { cleanup(dir) }

        mgr.add(URL(fileURLWithPath: "/tmp/a"), color: .red)
        mgr.add(URL(fileURLWithPath: "/tmp/b"), color: .red)
        mgr.add(URL(fileURLWithPath: "/tmp/c"), color: .blue)

        #expect(mgr.totalCount == 3)
    }

    @Test("save and reload preserves data")
    @MainActor func saveAndReload() {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("color-tag-persist-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let jsonPath = tmpDir.appendingPathComponent("color-labels.json")

        // Create, add, save
        let mgr1 = ColorTagManager(filePath: jsonPath)
        mgr1.add(URL(fileURLWithPath: "/tmp/persist1.txt"), color: .red)
        mgr1.add(URL(fileURLWithPath: "/tmp/persist2.txt"), color: .blue)
        mgr1.save()

        // Create new instance from same file
        let mgr2 = ColorTagManager(filePath: jsonPath)
        #expect(mgr2.count(for: .red) == 1)
        #expect(mgr2.count(for: .blue) == 1)
        #expect(mgr2.list(.red).count == 1)
        #expect(mgr2.list(.blue).count == 1)
    }

    @Test("colorsForFile returns correct colors")
    @MainActor func colorsForFile() {
        let (mgr, dir) = makeTempManager()
        defer { cleanup(dir) }

        let url = URL(fileURLWithPath: "/tmp/multi-color.txt")
        mgr.add(url, color: .red)
        mgr.add(url, color: .orange)

        let colors = mgr.colorsForFile(url)
        #expect(colors.contains(.red))
        #expect(colors.contains(.orange))
        #expect(!colors.contains(.blue))
        #expect(!colors.contains(.green))
    }

    @Test("version increments on every mutation")
    @MainActor func versionIncrements() {
        let (mgr, dir) = makeTempManager()
        defer { cleanup(dir) }

        let v0 = mgr.version
        mgr.add(URL(fileURLWithPath: "/tmp/v1"), color: .red)
        #expect(mgr.version == v0 + 1)

        mgr.remove(URL(fileURLWithPath: "/tmp/v1"), color: .red)
        #expect(mgr.version == v0 + 2)
    }
}

// MARK: - AppSettings Tests

@Suite("AppSettings")
struct AppSettingsTests {
    @Test("shared instance has valid defaults or loaded values")
    @MainActor func sharedExists() {
        let settings = AppSettings.shared
        // Font size should be reasonable (either default 12 or loaded value)
        #expect(settings.previewFontSize >= 8)
        #expect(settings.previewFontSize <= 32)
    }

    @Test("font size clamped by increase/decrease")
    @MainActor func fontSizeClamping() {
        let settings = AppSettings.shared
        let original = settings.previewFontSize

        // Set to max and try to go higher
        settings.previewFontSize = 32
        settings.increaseFontSize()
        #expect(settings.previewFontSize == 32)

        // Set to min and try to go lower
        settings.previewFontSize = 8
        settings.decreaseFontSize()
        #expect(settings.previewFontSize == 8)

        // Restore original
        settings.previewFontSize = original
    }

    @Test("preferred apps add and remove")
    @MainActor func preferredApps() {
        let settings = AppSettings.shared
        let testKey = "__test_ext_\(UUID().uuidString)__"

        settings.addPreferredApp(for: testKey, appPath: "/Applications/TextEdit.app")
        #expect(settings.getPreferredApps(for: testKey).contains("/Applications/TextEdit.app"))

        settings.removePreferredApp(for: testKey, appPath: "/Applications/TextEdit.app")
        #expect(!settings.getPreferredApps(for: testKey).contains("/Applications/TextEdit.app"))
    }

    @Test("normalizes empty extension to __empty__")
    @MainActor func emptyExtensionNormalized() {
        let settings = AppSettings.shared
        settings.addPreferredApp(for: "", appPath: "/tmp/test.app")
        #expect(settings.getPreferredApps(for: "").contains("/tmp/test.app"))
        settings.removePreferredApp(for: "", appPath: "/tmp/test.app")
    }
}

// MARK: - MovieManager Tests

@Suite("MovieManager Detection")
struct MovieDetectionTests {
    @Test("detects year in parentheses")
    func parenthesesYear() {
        let result = MovieManager.detectMovie(folderName: "The Matrix (1999)")
        #expect(result != nil)
        #expect(result?.title == "The Matrix")
        #expect(result?.year == "1999")
    }

    @Test("detects dot-separated title and year")
    func dotSeparated() {
        let result = MovieManager.detectMovie(folderName: "Inception.2010.1080p.BluRay")
        #expect(result != nil)
        #expect(result?.title == "Inception")
        #expect(result?.year == "2010")
    }

    @Test("detects space-separated title and year")
    func spaceSeparated() {
        let result = MovieManager.detectMovie(folderName: "Blade Runner 2049 2017")
        #expect(result != nil)
        // "2049" is picked up as year first (it's in valid range)
        #expect(result?.title == "Blade Runner")
        #expect(result?.year == "2049")
    }

    @Test("detects title with year in parentheses even when title has numbers")
    func titleWithNumbers() {
        // Parenthesized year takes priority
        let result = MovieManager.detectMovie(folderName: "Blade Runner 2049 (2017)")
        #expect(result != nil)
        #expect(result?.title == "Blade Runner 2049")
        #expect(result?.year == "2017")
    }

    @Test("detects underscore-separated title")
    func underscoreSeparated() {
        let result = MovieManager.detectMovie(folderName: "The_Dark_Knight_2008")
        #expect(result != nil)
        #expect(result?.title == "The Dark Knight")
        #expect(result?.year == "2008")
    }

    @Test("returns nil for folder without year")
    func noYear() {
        let result = MovieManager.detectMovie(folderName: "Documents")
        #expect(result == nil)
    }

    @Test("returns nil for year outside range")
    func yearOutOfRange() {
        let result = MovieManager.detectMovie(folderName: "Project 1850")
        #expect(result == nil)
    }

    @Test("strips release tags from title")
    func stripsReleaseTags() {
        let result = MovieManager.detectMovie(folderName: "Interstellar.2014.1080p.BluRay.x264")
        #expect(result != nil)
        #expect(result?.title == "Interstellar")
    }

    @Test("handles hyphen-separated names")
    func hyphenSeparated() {
        let result = MovieManager.detectMovie(folderName: "No-Country-for-Old-Men-2007")
        #expect(result != nil)
        #expect(result?.title == "No Country for Old Men")
        #expect(result?.year == "2007")
    }

    @Test("extracts title from video filename with extension")
    func videoFilename() {
        let result = MovieManager.detectMovie(folderName: "Cabeza.de.Vaca.1991.DVDRip.blablebliblobluao.avi")
        #expect(result != nil)
        #expect(result?.title == "Cabeza de Vaca")
        #expect(result?.year == "1991")
    }

    @Test("extracts title from mkv filename")
    func mkvFilename() {
        let result = MovieManager.detectMovie(folderName: "The.Shawshank.Redemption.1994.1080p.BluRay.x264.mkv")
        #expect(result != nil)
        #expect(result?.title == "The Shawshank Redemption")
        #expect(result?.year == "1994")
    }

    @Test("hasVideoFile detects video in folder")
    func hasVideoFile() throws {
        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory.appendingPathComponent("video-check-\(UUID().uuidString)")
        try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmpDir) }

        // No video yet
        #expect(!MovieManager.hasVideoFile(in: tmpDir))

        // Add a video file
        try "".write(to: tmpDir.appendingPathComponent("movie.mkv"), atomically: true, encoding: .utf8)
        #expect(MovieManager.hasVideoFile(in: tmpDir))
    }

    @Test("hasVideoFile ignores audio files")
    func ignoresAudio() throws {
        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory.appendingPathComponent("audio-check-\(UUID().uuidString)")
        try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmpDir) }

        try "".write(to: tmpDir.appendingPathComponent("soundtrack.mp3"), atomically: true, encoding: .utf8)
        try "".write(to: tmpDir.appendingPathComponent("audio.flac"), atomically: true, encoding: .utf8)
        #expect(!MovieManager.hasVideoFile(in: tmpDir))
    }
}

@Suite("MovieManager API")
struct MovieAPITests {
    @Test("fetches The Matrix folder and caches as .fe-movie.json")
    @MainActor func fetchMatrixFolder() async throws {
        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory.appendingPathComponent("movie-test-\(UUID().uuidString)")
        try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmpDir) }

        let movieDir = tmpDir.appendingPathComponent("The Matrix (1999)")
        try fm.createDirectory(at: movieDir, withIntermediateDirectories: true)

        let info = await MovieManager.shared.getMovieInfo(for: movieDir)
        #expect(info != nil)
        #expect(info?.title == "The Matrix")
        #expect(info?.year == "1999")
        #expect(info?.imdbID == "tt0133093")
        #expect(info?.director.contains("Wachowski") == true)
        #expect(info?.imdbRating != "N/A")
        #expect(info?.rottenTomatoesRating != "N/A")
        #expect(info?.topActors.count == 3)

        // Folder cache: .fe-movie.json inside the folder
        let cacheFile = movieDir.appendingPathComponent(".fe-movie.json")
        #expect(fm.fileExists(atPath: cacheFile.path))
        let data = try Data(contentsOf: cacheFile)
        let cached = try JSONDecoder().decode(MovieInfo.self, from: data)
        #expect(cached.title == "The Matrix")

        let json = String(data: data, encoding: .utf8) ?? "failed to read"
        print("=== .fe-movie.json for folder ===")
        print(json)
        print("=== end ===")

        // Second call should use cache
        let cached2 = await MovieManager.shared.getMovieInfo(for: movieDir)
        #expect(cached2?.title == "The Matrix")
    }

    @Test("fetches movie file and caches as .fe-FILENAME.json")
    @MainActor func fetchMovieFile() async throws {
        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory.appendingPathComponent("movie-file-test-\(UUID().uuidString)")
        try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmpDir) }

        let movieFile = tmpDir.appendingPathComponent("Inception.2010.1080p.BluRay.mkv")
        try "".write(to: movieFile, atomically: true, encoding: .utf8)

        let info = await MovieManager.shared.getMovieInfo(for: movieFile)
        #expect(info != nil)
        #expect(info?.title == "Inception")

        // File cache: .fe-Inception.2010.1080p.BluRay.mkv.json in same dir
        let cacheFile = tmpDir.appendingPathComponent(".fe-Inception.2010.1080p.BluRay.mkv.json")
        #expect(fm.fileExists(atPath: cacheFile.path))
        let data = try Data(contentsOf: cacheFile)
        let cached = try JSONDecoder().decode(MovieInfo.self, from: data)
        #expect(cached.title == "Inception")

        let json = String(data: data, encoding: .utf8) ?? "failed to read"
        print("=== .fe-FILENAME.json for file ===")
        print(json)
        print("=== end ===")
    }
}

// MARK: - Search Debounce Tests

@Suite("Search Debounce")
struct SearchDebounceTests {
    @Test("empty search clears results")
    @MainActor func emptySearchClears() {
        let manager = FileExplorerManager()
        manager.performSearch("")
        #expect(manager.searchResults.isEmpty)
        #expect(!manager.isSearchRunning)
    }

    @Test("whitespace-only search clears results")
    @MainActor func whitespaceSearchClears() {
        let manager = FileExplorerManager()
        manager.performSearch("   ")
        #expect(manager.searchResults.isEmpty)
        #expect(!manager.isSearchRunning)
    }
}

// MARK: - ShortcutsManager Pin/Unpin Tests

@Suite("ShortcutsManager Pin")
struct ShortcutsManagerPinTests {
    @MainActor private func makeTempManager() -> (ShortcutsManager, URL) {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shortcuts-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let mgr = ShortcutsManager(configDir: tmpDir)
        return (mgr, tmpDir)
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    @Test("addFolder pins a directory and it appears in customFolders")
    @MainActor func pinFolder() {
        let (mgr, dir) = makeTempManager()
        defer { cleanup(dir) }

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("pin-target-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        mgr.addFolder(folder)
        #expect(mgr.customFolders.contains(where: { $0.path == folder.path }))
    }

    @Test("pinned folder appears in allShortcuts as non-built-in")
    @MainActor func pinnedInAllShortcuts() {
        let (mgr, dir) = makeTempManager()
        defer { cleanup(dir) }

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("pin-shortcut-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        mgr.addFolder(folder)
        let match = mgr.allShortcuts.first(where: { $0.url.path == folder.path })
        #expect(match != nil)
        #expect(match?.isBuiltIn == false)
        #expect(match?.name == folder.lastPathComponent)
    }

    @Test("duplicate addFolder does not create duplicates")
    @MainActor func noDuplicatePin() {
        let (mgr, dir) = makeTempManager()
        defer { cleanup(dir) }

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("dup-pin-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        mgr.addFolder(folder)
        mgr.addFolder(folder)
        let count = mgr.customFolders.filter { $0.path == folder.path }.count
        #expect(count == 1)
    }

    @Test("removeFolder unpins a directory")
    @MainActor func unpinFolder() {
        let (mgr, dir) = makeTempManager()
        defer { cleanup(dir) }

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("unpin-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        mgr.addFolder(folder)
        #expect(mgr.customFolders.contains(where: { $0.path == folder.path }))

        mgr.removeFolder(folder)
        #expect(!mgr.customFolders.contains(where: { $0.path == folder.path }))
    }

    @Test("pinned folders persist to disk and reload")
    @MainActor func persistAndReload() {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shortcuts-persist-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("persist-pin-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        // Pin and save
        let mgr1 = ShortcutsManager(configDir: tmpDir)
        mgr1.addFolder(folder)

        // Reload from same config dir
        let mgr2 = ShortcutsManager(configDir: tmpDir)
        #expect(mgr2.customFolders.contains(where: { $0.path == folder.path }))
    }

    @Test("moveFolder reorders pinned folders")
    @MainActor func reorderFolders() {
        let (mgr, dir) = makeTempManager()
        defer { cleanup(dir) }

        let a = FileManager.default.temporaryDirectory.appendingPathComponent("order-a-\(UUID().uuidString)")
        let b = FileManager.default.temporaryDirectory.appendingPathComponent("order-b-\(UUID().uuidString)")
        let c = FileManager.default.temporaryDirectory.appendingPathComponent("order-c-\(UUID().uuidString)")
        for f in [a, b, c] {
            try? FileManager.default.createDirectory(at: f, withIntermediateDirectories: true)
        }
        defer { for f in [a, b, c] { try? FileManager.default.removeItem(at: f) } }

        mgr.addFolder(a)
        mgr.addFolder(b)
        mgr.addFolder(c)
        #expect(mgr.customFolders[0].path == a.path)

        // Move last to first
        mgr.moveFolder(from: IndexSet(integer: 2), to: 0)
        #expect(mgr.customFolders[0].path == c.path)
        #expect(mgr.customFolders[1].path == a.path)
        #expect(mgr.customFolders[2].path == b.path)
    }
}
