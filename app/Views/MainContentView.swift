import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ResizableSplitView<Top: View, Bottom: View>: View {
    @ObservedObject private var settings = AppSettings.shared
    @ViewBuilder let top: () -> Top
    @ViewBuilder let bottom: () -> Bottom

    @State private var isDragging = false
    @State private var dragSplit: CGFloat? = nil

    var body: some View {
        GeometryReader { geometry in
            let totalHeight = geometry.size.height
            let activeSplit = dragSplit ?? settings.previewPaneSplit
            let topHeight = totalHeight * activeSplit
            let bottomHeight = totalHeight - topHeight - 8 // 8 for divider

            VStack(spacing: 0) {
                top()
                    .frame(height: max(100, topHeight))

                // Draggable divider
                Rectangle()
                    .fill(isDragging ? Color.accentColor : Color(NSColor.separatorColor))
                    .frame(height: 8)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        if hovering {
                            NSCursor.resizeUpDown.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 2)
                            .onChanged { value in
                                isDragging = true
                                let newTopHeight = totalHeight * settings.previewPaneSplit + value.translation.height
                                let newSplit = newTopHeight / totalHeight
                                dragSplit = min(0.8, max(0.2, newSplit))
                            }
                            .onEnded { _ in
                                if let s = dragSplit {
                                    settings.previewPaneSplit = s
                                }
                                dragSplit = nil
                                isDragging = false
                            }
                    )

                bottom()
                    .frame(height: max(100, bottomHeight))
            }
        }
    }
}

// Preview type detected async to avoid blocking the main thread with disk I/O
enum PreviewKind: Equatable {
    case movie, imageGallery, standard, none
}

private let previewImageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "bmp", "webp", "heic", "heif", "tiff", "tif", "svg", "avif"]

func detectPreviewKind(for url: URL) -> PreviewKind {
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return .none }

    if isDir.boolValue {
        if MovieManager.detectMovie(folderName: url.lastPathComponent) != nil,
           MovieManager.hasVideoFile(in: url) {
            return .movie
        }
        if let contents = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]),
           contents.contains(where: { previewImageExtensions.contains($0.pathExtension.lowercased()) }) {
            return .imageGallery
        }
    } else {
        let ext = url.pathExtension.lowercased()
        if MovieManager.videoExtensions.contains(ext),
           MovieManager.detectMovie(folderName: url.lastPathComponent) != nil {
            return .movie
        }
    }

    if PreviewType.detect(for: url) != .none {
        return .standard
    }

    return .none
}

struct MainContentView: View {
    @ObservedObject var manager: FileExplorerManager
    @ObservedObject private var settings = AppSettings.shared
    @State private var isDraggingRightPane = false
    @State private var rightPaneDragStartWidth: CGFloat = 0
    @State private var dragRightPaneWidth: CGFloat? = nil

    @State private var previewKind: PreviewKind = .none

    var body: some View {
        HStack(spacing: 0) {
            // Main pane (browser, selection, or search)
            MainPane(manager: manager)

                // Draggable divider for right pane
                Rectangle()
                    .fill(isDraggingRightPane ? Color.accentColor : Color(NSColor.separatorColor))
                    .frame(width: isDraggingRightPane ? 3 : 1)
                    .padding(.horizontal, 2)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        if hovering {
                            NSCursor.resizeLeftRight.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 2)
                            .onChanged { value in
                                if !isDraggingRightPane {
                                    isDraggingRightPane = true
                                    rightPaneDragStartWidth = settings.rightPaneWidth
                                }
                                let newWidth = min(900, max(200, rightPaneDragStartWidth - value.translation.width))
                                dragRightPaneWidth = newWidth
                            }
                            .onEnded { _ in
                                if let w = dragRightPaneWidth {
                                    settings.rightPaneWidth = w
                                }
                                dragRightPaneWidth = nil
                                isDraggingRightPane = false
                            }
                    )

                // Right pane: actions + preview
                VStack(spacing: 0) {
                    if manager.currentPane == .iphone {
                        iPhoneActionsPane(manager: manager)
                    } else {
                        ActionsPane(manager: manager)
                    }

                    if settings.showPreviewPane {
                        // Preview below actions
                        if let selected = manager.selectedItem {
                            switch previewKind {
                            case .movie:
                                Divider()
                                MoviePreviewView(folderURL: selected)
                                    .id(selected)
                                    .frame(maxHeight: .infinity)
                                    .background(Color.white)
                            case .imageGallery:
                                Divider()
                                FolderGalleryPreview(folderURL: selected)
                                    .id(selected)
                                    .frame(maxHeight: .infinity)
                                    .background(Color.white)
                            case .standard:
                                Divider()
                                PreviewPane(url: selected, manager: manager)
                                    .id(selected)
                                    .frame(maxHeight: .infinity)
                                    .background(Color.white)
                            case .none:
                                Spacer()
                            }
                        } else if manager.hasImages {
                            Divider()
                            FolderGalleryPreview(folderURL: manager.currentPath)
                                .frame(maxHeight: .infinity)
                                .background(Color.white)
                        } else {
                            Spacer()
                        }
                    } else {
                        Spacer()
                    }
                }
                .frame(width: dragRightPaneWidth ?? settings.rightPaneWidth)
                .background(Color(red: 0.98, green: 0.976, blue: 0.96))
                .task(id: manager.selectedItem) {
                    guard let url = manager.selectedItem else {
                        previewKind = .none
                        return
                    }
                    let u = url
                    let kind = await Task.detached(priority: .userInitiated) {
                        detectPreviewKind(for: u)
                    }.value
                    if !Task.isCancelled {
                        previewKind = kind
                    }
                }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .background(KeyEventHandlingView(manager: manager))
        .sheet(isPresented: Binding(
            get: { manager.renamingItem != nil },
            set: { if !$0 { manager.cancelRename() } }
        )) {
            RenameDialog(manager: manager)
        }
    }
}

struct RenameDialog: View {
    @ObservedObject var manager: FileExplorerManager

    private var isDirectory: Bool {
        guard let item = manager.renamingItem else { return false }
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir)
        return isDir.boolValue
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: isDirectory ? "folder.fill" : "doc.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.blue)
                Text("Rename")
                    .textStyle(.default, weight: .semibold)
                Spacer()
            }

            TextField("Name", text: $manager.renameText)
                .styledInput()
                .onSubmit {
                    if !manager.renameText.isEmpty {
                        manager.confirmRename()
                    }
                }

            HStack {
                Button("Cancel") {
                    manager.cancelRename()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Rename") {
                    if !manager.renameText.isEmpty {
                        manager.confirmRename()
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(manager.renameText.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 600)
    }
}

struct KeyEventHandlingView: NSViewRepresentable {
    @ObservedObject var manager: FileExplorerManager

    func makeNSView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        view.manager = manager
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: KeyCaptureView, context: Context) {
        nsView.manager = manager
        // Reclaim focus when no sheet/dialog is active and we don't have focus
        if manager.renamingItem == nil && !manager.isSearching && !manager.showItemDialog {
            if let window = nsView.window {
                let responder = window.firstResponder
                // Reclaim if focus is on the window itself (sheet just closed) or already on us
                if responder === window || responder === nsView || responder is KeyCaptureView {
                    if !(responder is KeyCaptureView) {
                        DispatchQueue.main.async {
                            window.makeFirstResponder(nsView)
                        }
                    }
                }
            }
        }
    }
}

class KeyCaptureView: NSView {
    var manager: FileExplorerManager?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard let manager else {
            super.keyDown(with: event)
            return
        }

        if handleRenameMode(event, manager: manager) { return }
        if handleTabCycle(event, manager: manager) { return }
        if handleSidebarMode(event, manager: manager) { return }
        if handleRightPaneMode(event, manager: manager) { return }
        if handleOpenWithPreferred(event, manager: manager) { return }
        if handleSearchNavigation(event, manager: manager) { return }
        if handleColorTagNavigation(event, manager: manager) { return }
        if handleNormalMode(event, manager: manager) { return }

        super.keyDown(with: event)
    }

    private func handleRenameMode(_ event: NSEvent, manager: FileExplorerManager) -> Bool {
        guard manager.renamingItem != nil else { return false }

        if event.keyCode == 53 {
            manager.cancelRename()
            DispatchQueue.main.async {
                self.window?.makeFirstResponder(self)
            }
        }
        return true
    }

    private func handleTabCycle(_ event: NSEvent, manager: FileExplorerManager) -> Bool {
        guard event.keyCode == 48 else { return false }

        if manager.sidebarFocused {
            manager.unfocusSidebar()
        } else if manager.rightPaneFocused {
            manager.unfocusRightPane()
            manager.focusSidebar()
        } else {
            manager.focusRightPane()
        }
        return true
    }

    private func handleSidebarMode(_ event: NSEvent, manager: FileExplorerManager) -> Bool {
        guard manager.sidebarFocused else { return false }

        switch event.keyCode {
        case 125:
            manager.sidebarSelectNext()
        case 126:
            manager.sidebarSelectPrevious()
        case 124, 36:
            manager.sidebarActivate()
        case 53:
            manager.unfocusSidebar()
        default:
            break
        }
        return true
    }

    private func handleRightPaneMode(_ event: NSEvent, manager: FileExplorerManager) -> Bool {
        guard manager.rightPaneFocused else { return false }

        switch event.keyCode {
        case 125:
            manager.rightPaneSelectNext()
        case 126:
            manager.rightPaneSelectPrevious()
        case 36:
            manager.rightPaneActivate()
        case 123, 53:
            manager.unfocusRightPane()
        default:
            break
        }
        return true
    }

    private func handleOpenWithPreferred(_ event: NSEvent, manager: FileExplorerManager) -> Bool {
        guard event.keyCode == 31 && event.modifierFlags.contains(.command) else { return false }

        if manager.isSearching {
            if manager.listCursorIndex >= 0 && manager.listCursorIndex < manager.searchResults.count {
                let item = manager.searchResults[manager.listCursorIndex]
                manager.listActivateItem(url: item.url, isDirectory: item.isDirectory)
            }
            return true
        }

        if case .colorTag(let tagColor) = manager.currentPane {
            let files = ColorTagManager.shared.list(tagColor)
            if manager.listCursorIndex >= 0 && manager.listCursorIndex < files.count {
                let file = files[manager.listCursorIndex]
                if file.exists {
                    manager.listActivateItem(url: file.url, isDirectory: file.isDirectory)
                }
            }
            return true
        }

        if let item = manager.selectedItem {
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: item.path, isDirectory: &isDirectory)
            if isDirectory.boolValue {
                manager.navigateTo(item)
            } else {
                manager.openFileWithPreferredApp(item)
            }
        }
        return true
    }

    private func handleSearchNavigation(_ event: NSEvent, manager: FileExplorerManager) -> Bool {
        guard manager.isSearching else { return false }

        switch event.keyCode {
        case 125:
            manager.listSelectNext(count: manager.searchResults.count)
            if manager.listCursorIndex >= 0 && manager.listCursorIndex < manager.searchResults.count {
                let item = manager.searchResults[manager.listCursorIndex]
                manager.selectItem(at: -1, url: item.url)
            }
            return true
        case 126:
            manager.listSelectPrevious(count: manager.searchResults.count)
            if manager.listCursorIndex >= 0 && manager.listCursorIndex < manager.searchResults.count {
                let item = manager.searchResults[manager.listCursorIndex]
                manager.selectItem(at: -1, url: item.url)
            }
            return true
        case 36:
            if manager.listCursorIndex >= 0 && manager.listCursorIndex < manager.searchResults.count {
                let item = manager.searchResults[manager.listCursorIndex]
                manager.listActivateItem(url: item.url, isDirectory: item.isDirectory)
            }
            return true
        case 53:
            manager.cancelSearch()
            return true
        default:
            return false
        }
    }

    private func handleColorTagNavigation(_ event: NSEvent, manager: FileExplorerManager) -> Bool {
        guard case .colorTag(let tagColor) = manager.currentPane else { return false }

        let files = ColorTagManager.shared.list(tagColor)
        switch event.keyCode {
        case 125:
            manager.listSelectNext(count: files.count)
            if manager.listCursorIndex >= 0 && manager.listCursorIndex < files.count {
                manager.selectItem(at: -1, url: files[manager.listCursorIndex].url)
            }
            return true
        case 126:
            manager.listSelectPrevious(count: files.count)
            if manager.listCursorIndex >= 0 && manager.listCursorIndex < files.count {
                manager.selectItem(at: -1, url: files[manager.listCursorIndex].url)
            }
            return true
        case 36:
            if manager.listCursorIndex >= 0 && manager.listCursorIndex < files.count {
                let file = files[manager.listCursorIndex]
                if file.exists {
                    manager.listActivateItem(url: file.url, isDirectory: file.isDirectory)
                }
            }
            return true
        case 53:
            manager.currentPane = .browser
            manager.listCursorIndex = -1
            return true
        default:
            return false
        }
    }

    private func handleNormalMode(_ event: NSEvent, manager: FileExplorerManager) -> Bool {
        switch event.keyCode {
        case 0:
            if event.modifierFlags.contains(.control) || event.modifierFlags.contains(.command) {
                manager.selectAllFiles()
                return true
            }
        case 8:
            if event.modifierFlags.contains(.control) {
                if let item = manager.selectedItem {
                    manager.toggleFileSelection(item)
                }
                return true
            }
        case 15:
            if event.modifierFlags.contains(.control) {
                manager.refresh()
                return true
            }
        case 125:
            if event.modifierFlags.contains(.command) {
                navigateIntoSelectedDirectoryIfNeeded(manager)
            } else {
                manager.selectNext()
            }
            return true
        case 126:
            if event.modifierFlags.contains(.command) {
                manager.navigateUp()
            } else {
                manager.selectPrevious()
            }
            return true
        case 123:
            manager.navigateUp()
            return true
        case 124:
            navigateIntoSelectedDirectoryIfNeeded(manager)
            return true
        case 49:
            manager.toggleGlobalSelection()
            return true
        case 36:
            if manager.selectedItem != nil {
                manager.startRename()
            }
            return true
        case 51:
            if event.modifierFlags.contains(.command) {
                if let item = manager.selectedItem {
                    manager.moveToTrash(item)
                }
            } else {
                manager.goBack()
            }
            return true
        case 115:
            manager.selectFirst()
            return true
        case 119:
            manager.selectLast()
            return true
        case 53:
            if manager.browserViewMode != .files {
                manager.browserViewMode = .files
            }
            return true
        default:
            if let chars = event.characters, chars.count == 1,
               let c = chars.first, c.isLetter,
               !event.modifierFlags.contains(.command),
               !event.modifierFlags.contains(.control) {
                manager.jumpToLetter(c)
                return true
            }
        }

        return false
    }

    private func navigateIntoSelectedDirectoryIfNeeded(_ manager: FileExplorerManager) {
        guard let item = manager.selectedItem else { return }

        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: item.path, isDirectory: &isDirectory)
        guard isDirectory.boolValue else { return }

        manager.navigateTo(item)
        if manager.selectedItem == nil && !manager.allItems.isEmpty {
            manager.selectItem(at: 0, url: manager.allItems[0].url)
        }
    }
}

struct ToolbarView: View {
    @ObservedObject var manager: FileExplorerManager

    var body: some View {
        HStack(spacing: 8) {
            Button(action: { manager.goBack() }) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .disabled(!manager.canGoBack)

            Button(action: { manager.goForward() }) {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .disabled(!manager.canGoForward)

            Spacer()

            Text(manager.currentPath.lastPathComponent.isEmpty ? "Root" : manager.currentPath.lastPathComponent)
                .textStyle(.default, weight: .semibold)
                .lineLimit(1)

            Spacer()

            Button(action: { manager.navigateUp() }) {
                Image(systemName: "arrow.up")
            }
            .buttonStyle(.borderless)
            .disabled(manager.currentPath.path == "/")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct BreadcrumbView: View {
    @ObservedObject var manager: FileExplorerManager
    @ObservedObject var shortcutsManager = ShortcutsManager.shared
    @ObservedObject var folderIconManager = FolderIconManager.shared
    @State private var showEmojiPicker = false

    private var pathComponents: [(name: String, url: URL)] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var components: [(String, URL)] = []
        var current = manager.currentPath

        while current.path != "/" && !current.path.isEmpty {
            if current.path == home.path {
                components.insert((current.lastPathComponent, current), at: 0)
                return components
            }
            components.insert((current.lastPathComponent, current), at: 0)
            current = current.deletingLastPathComponent()
        }
        components.insert(("Root", URL(fileURLWithPath: "/")), at: 0)

        return components
    }

    private var isPinned: Bool {
        shortcutsManager.customFolders.contains(where: { $0.path == manager.currentPath.path })
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(pathComponents.enumerated()), id: \.offset) { index, component in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .textStyle(.small)
                        .foregroundColor(.secondary)
                }

                Button(action: { manager.navigateTo(component.url) }) {
                    Text(component.name)
                        .textStyle(.buttons)
                        .foregroundColor(index == pathComponents.count - 1 ? .primary : .blue)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Icon button (only when pinned)
            if isPinned {
                Button(action: { showEmojiPicker = true }) {
                    Image(systemName: "face.smiling")
                        .textStyle(.small)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Set folder icon")
                .popover(isPresented: $showEmojiPicker, arrowEdge: .bottom) {
                    EmojiPickerView(
                        folderURL: manager.currentPath,
                        onSelect: { emoji in
                            folderIconManager.setEmoji(emoji, for: manager.currentPath)
                        },
                        onRemove: {
                            folderIconManager.removeEmoji(for: manager.currentPath)
                        },
                        onDismiss: { showEmojiPicker = false },
                        hasExisting: folderIconManager.emoji(for: manager.currentPath) != nil
                    )
                    .interactiveDismissDisabled()
                }
            }

            // Pin button
            Button(action: {
                if isPinned {
                    shortcutsManager.removeFolder(manager.currentPath)
                } else {
                    shortcutsManager.addFolder(manager.currentPath)
                }
            }) {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .textStyle(.small)
                    .foregroundColor(isPinned ? .orange : .secondary)
            }
            .buttonStyle(.plain)
            .help(isPinned ? "Unpin folder" : "Pin folder")

        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
}

struct ActionButtonBar: View {
    @ObservedObject var manager: FileExplorerManager
    @ObservedObject private var settings = AppSettings.shared

    @State private var showNewFolderDialog = false
    @State private var newFolderName = ""

    var body: some View {
        HStack(spacing: 8) {
            Button(action: {
                manager.toggleShowHidden()
            }) {
                Text(manager.showHidden ? "hide hidden" : "show hidden")
                    .textStyle(.buttons)
            }
            .buttonStyle(.bordered)

            Button(action: {
                if manager.isSearching {
                    manager.cancelSearch()
                } else {
                    manager.startSearch()
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: manager.isSearching ? "xmark" : "magnifyingglass")
                        .textStyle(.buttons)
                    Text(manager.isSearching ? "Close" : "Search")
                        .textStyle(.buttons)
                }
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("f", modifiers: .command)

            Divider()
                .frame(height: 20)

            // Sort buttons
            Text("Sort by")
                .textStyle(.buttons)
                .lineLimit(1)
                .fixedSize()
                .foregroundColor(.secondary)

            HStack(spacing: 0) {
                ForEach(SortMode.allCases, id: \.self) { mode in
                    Button(action: {
                        manager.sortMode = mode
                    }) {
                        Text(mode.rawValue)
                            .textStyle(.buttons, weight: manager.sortMode == mode ? .semibold : .regular)
                            .lineLimit(1)
                            .fixedSize()
                            .foregroundColor(manager.sortMode == mode ? .white : .primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                manager.sortMode == mode ?
                                Color.accentColor : Color.clear
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )

            Divider()
                .frame(height: 20)

            // New file/folder buttons
            Button(action: {
                newFolderName = "New Folder"
                showNewFolderDialog = true
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "folder.badge.plus")
                        .textStyle(.buttons)
                    Text("Folder")
                        .textStyle(.buttons)
                }
            }
            .buttonStyle(.bordered)
            .help("Create new folder")

            Button(action: {
                manager.createNewFile()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "doc.badge.plus")
                        .textStyle(.buttons)
                    Text("File")
                        .textStyle(.buttons)
                }
            }
            .buttonStyle(.bordered)
            .help("Create new text file")

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .sheet(isPresented: $showNewFolderDialog) {
            NewFolderDialog(folderName: $newFolderName, isPresented: $showNewFolderDialog) {
                manager.createNewFolder(named: newFolderName)
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
    }
}

struct NewFolderDialog: View {
    @Binding var folderName: String
    @Binding var isPresented: Bool
    var onCreate: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 24))
                    .foregroundColor(.blue)
                Text("New Folder")
                    .textStyle(.default, weight: .semibold)
                Spacer()
            }

            TextField("Folder name", text: $folderName)
                .styledInput()
                .onSubmit {
                    if !folderName.isEmpty {
                        onCreate()
                        isPresented = false
                    }
                }

            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Create") {
                    if !folderName.isEmpty {
                        onCreate()
                        isPresented = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(folderName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 300)
    }
}

struct TableHeaderView: View {
    var showModified: Bool = true

    var body: some View {
        HStack(spacing: 0) {
            Text("Name")
                .frame(minWidth: 250, alignment: .leading)

            Spacer()

            if showModified {
                Text("Modified ago")
                    .frame(width: 180, alignment: .leading)
            }

            Text("Size")
                .frame(width: 80, alignment: .trailing)
        }
        .textStyle(.small, weight: .medium)
        .foregroundColor(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
    }
}

// MARK: - Search TextField (auto-focus, Escape to cancel)

struct SearchTextField: NSViewRepresentable {
    @Binding var text: String
    var onCancel: () -> Void

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = "Search files…"
        field.font = NSFont.systemFont(ofSize: 15)
        field.delegate = context.coordinator
        field.focusRingType = .none
        field.sendsWholeSearchString = false
        field.sendsSearchStringImmediately = true
        // Hide the built-in cancel button — we have our own
        if let cell = field.cell as? NSSearchFieldCell {
            cell.cancelButtonCell = nil
        }
        // Auto-focus
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
        }
        return field
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSSearchFieldDelegate {
        let parent: SearchTextField

        init(_ parent: SearchTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onCancel()
                return true
            }
            return false
        }
    }
}

// FileTreeView, AncestorRow, FileTreeRow -> FileTreeView.swift
// FileTableView, FileTableRow -> FileTableView.swift
// FileDetailsView, DetailRow, EmptyFolderView, EmptySearchResultsView -> HelperViews.swift
// RenameTextField -> HelperViews.swift
// FolderGalleryPreview, FolderGalleryThumbnail -> FolderGalleryPreview.swift
