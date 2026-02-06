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
        #expect(MainPaneType.browser == MainPaneType.browser)
        #expect(MainPaneType.iphone == MainPaneType.iphone)
        #expect(MainPaneType.colorTag(.red) == MainPaneType.colorTag(.red))
        #expect(MainPaneType.colorTag(.red) != MainPaneType.colorTag(.blue))
        #expect(MainPaneType.browser != MainPaneType.selection)
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
        #expect(sel.count == 0)
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
        #expect(sel.count == 0)
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
        #expect(sel.count == 0)
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
        #expect(paths.count > 0)
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
