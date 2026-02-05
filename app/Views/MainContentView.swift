import SwiftUI
import AppKit
import WebKit
import UniformTypeIdentifiers

struct ResizableSplitView<Top: View, Bottom: View>: View {
    @ObservedObject private var settings = AppSettings.shared
    @ViewBuilder let top: () -> Top
    @ViewBuilder let bottom: () -> Bottom

    @State private var isDragging = false

    var body: some View {
        GeometryReader { geometry in
            let totalHeight = geometry.size.height
            let topHeight = totalHeight * settings.previewPaneSplit
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
                        DragGesture()
                            .onChanged { value in
                                isDragging = true
                                let newTopHeight = topHeight + value.translation.height
                                let newSplit = newTopHeight / totalHeight
                                // Clamp between 20% and 80%
                                settings.previewPaneSplit = min(0.8, max(0.2, newSplit))
                            }
                            .onEnded { _ in
                                isDragging = false
                            }
                    )

                bottom()
                    .frame(height: max(100, bottomHeight))
            }
        }
    }
}

struct MainContentView: View {
    @ObservedObject var manager: FileExplorerManager
    @ObservedObject private var settings = AppSettings.shared
    @State private var isDraggingRightPane = false

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                // Main pane (browser, selection, or search)
                MainPane(manager: manager)

                // Draggable divider for right pane
                Rectangle()
                    .fill(isDraggingRightPane ? Color.accentColor : Color(NSColor.separatorColor))
                    .frame(width: isDraggingRightPane ? 3 : 1)
                    .onHover { hovering in
                        if hovering {
                            NSCursor.resizeLeftRight.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                isDraggingRightPane = true
                                // Dragging left increases width, right decreases
                                let newWidth = settings.rightPaneWidth - value.translation.width
                                settings.rightPaneWidth = min(500, max(200, newWidth))
                            }
                            .onEnded { _ in
                                isDraggingRightPane = false
                            }
                    )

                // Actions pane (right side) - always visible
                if manager.currentPane == .iphone {
                    iPhoneActionsPane(manager: manager)
                        .frame(width: settings.rightPaneWidth)
                } else {
                    ActionsPane(manager: manager)
                        .frame(width: settings.rightPaneWidth)
                }
            }

            // Fuzzy search overlay
            if manager.fzfSearch.isSearching {
                FuzzySearchView(
                    fzfSearch: manager.fzfSearch,
                    onOpenFolder: { manager.navigateTo($0) }
                )
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .background(KeyEventHandlingView(manager: manager))
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
        // Reclaim focus when not renaming
        if manager.renamingItem == nil {
            DispatchQueue.main.async {
                if nsView.window?.firstResponder != nsView {
                    nsView.window?.makeFirstResponder(nsView)
                }
            }
        }
    }
}

class KeyCaptureView: NSView {
    var manager: FileExplorerManager?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard let manager = manager else {
            super.keyDown(with: event)
            return
        }

        // If renaming, let the text field handle all input except Escape
        if manager.renamingItem != nil {
            if event.keyCode == 53 { // Escape - cancel rename
                manager.cancelRename()
                // Reclaim focus
                DispatchQueue.main.async {
                    self.window?.makeFirstResponder(self)
                }
            }
            // Let all other keys go to text field
            return
        }

        // Handle fuzzy search mode
        if manager.fzfSearch.isSearching {
            switch event.keyCode {
            case 53: // Escape - cancel fuzzy search
                manager.fzfSearch.cancel()
            case 125: // Down arrow
                manager.fzfSearch.selectNext()
            case 126: // Up arrow
                manager.fzfSearch.selectPrevious()
            case 36: // Return/Enter - open selected result
                if let url = manager.fzfSearch.selectedURL {
                    var isDir: ObjCBool = false
                    FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                    manager.fzfSearch.cancel()
                    if isDir.boolValue {
                        manager.navigateTo(url)
                    }
                }
            case 51: // Delete/Backspace
                manager.fzfSearch.backspace()
            default:
                // Type characters into fuzzy search
                if let chars = event.characters, !chars.isEmpty {
                    let char = chars.first!
                    if char.isLetter || char.isNumber || char == "/" || char == "." || char == "_" || char == "-" || char == " " {
                        manager.fzfSearch.appendChar(String(char))
                    }
                }
            }
            return
        }

        // Normal mode - Finder-like behavior
        switch event.keyCode {
        case 0: // A key - check for Ctrl+A or Cmd+A
            if event.modifierFlags.contains(.control) || event.modifierFlags.contains(.command) {
                manager.selectAllFiles()
                return
            }
        case 3: // F key - check for Ctrl+F
            if event.modifierFlags.contains(.control) {
                manager.fzfSearch.start(from: manager.currentPath)
                return
            }
        case 125: // Down arrow - select next
            manager.selectNext()
        case 126: // Up arrow - select previous
            manager.selectPrevious()
        case 123: // Left arrow - go back/up
            manager.goBack()
        case 124: // Right arrow - enter folder or open file
            if let item = manager.selectedItem {
                var isDirectory: ObjCBool = false
                FileManager.default.fileExists(atPath: item.path, isDirectory: &isDirectory)
                if isDirectory.boolValue {
                    manager.navigateTo(item)
                } else {
                    NSWorkspace.shared.open(item)
                }
            }
        case 49: // Space - quick look / toggle selection
            manager.toggleGlobalSelection()
        case 36: // Return/Enter - rename (Finder behavior)
            if manager.selectedItem != nil {
                manager.startRename()
            }
        case 51: // Delete/Backspace - go back
            if event.modifierFlags.contains(.command) {
                // Cmd+Delete - move to trash
                if let item = manager.selectedItem {
                    manager.moveToTrash(item)
                }
            } else {
                manager.goBack()
            }
        case 115: // Home
            manager.selectFirst()
        case 119: // End
            manager.selectLast()
        case 53: // Escape
            break
        default:
            // Start fuzzy search when typing letters/numbers
            if let chars = event.characters, !chars.isEmpty {
                let char = chars.first!
                if char.isLetter || char.isNumber {
                    manager.fzfSearch.start(from: manager.currentPath)
                    manager.fzfSearch.appendChar(String(char))
                    return
                }
            }
            super.keyDown(with: event)
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
                .font(.headline)
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
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                Button(action: { manager.navigateTo(component.url) }) {
                    Text(component.name)
                        .font(.system(size: 13))
                        .foregroundColor(index == pathComponents.count - 1 ? .primary : .blue)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Pin button
            Button(action: {
                if isPinned {
                    shortcutsManager.removeFolder(manager.currentPath)
                } else {
                    shortcutsManager.addFolder(manager.currentPath)
                }
            }) {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 12))
                    .foregroundColor(isPinned ? .orange : .secondary)
            }
            .buttonStyle(.plain)
            .help(isPinned ? "Unpin folder" : "Pin folder")

            // Search button
            Button(action: {
                manager.fzfSearch.start(from: manager.currentPath)
            }) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Search in folder (Ctrl+F)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
}

struct ActionButtonBar: View {
    @ObservedObject var manager: FileExplorerManager
    @ObservedObject private var settings = AppSettings.shared
    @State private var showYouTubeSheet = false
    @State private var showNewFolderDialog = false
    @State private var newFolderName = ""

    var body: some View {
        HStack(spacing: 8) {
            Button(action: {
                manager.toggleShowHidden()
            }) {
                Text(manager.showHidden ? "hide hidden" : "show hidden")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)

            Divider()
                .frame(height: 20)

            // Sort buttons
            Text("Sort by")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            HStack(spacing: 0) {
                ForEach(SortMode.allCases, id: \.self) { mode in
                    Button(action: {
                        manager.sortMode = mode
                    }) {
                        Text(mode.rawValue)
                            .font(.system(size: 12, weight: manager.sortMode == mode ? .semibold : .regular))
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
                        .font(.system(size: 12))
                    Text("Folder")
                        .font(.system(size: 12))
                }
            }
            .buttonStyle(.bordered)
            .help("Create new folder")

            Button(action: {
                manager.createNewFile()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 12))
                    Text("File")
                        .font(.system(size: 12))
                }
            }
            .buttonStyle(.bordered)
            .help("Create new text file")

            // YouTube download button
            Button(action: {
                showYouTubeSheet = true
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                    Text("YouTube")
                        .font(.system(size: 12))
                }
            }
            .buttonStyle(.bordered)
            .help("Download from YouTube")

            Spacer()

            Button(action: {
                settings.showPreviewPane.toggle()
            }) {
                Image(systemName: settings.showPreviewPane ? "eye" : "eye.slash")
                    .font(.system(size: 13))
            }
            .buttonStyle(.bordered)
            .help(settings.showPreviewPane ? "Hide preview" : "Show preview")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .sheet(isPresented: $showYouTubeSheet) {
            YouTubeDownloadSheet(downloadPath: manager.currentPath, onComplete: {
                manager.refresh()
            })
        }
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
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
            }

            TextField("Folder name", text: $folderName)
                .textFieldStyle(.roundedBorder)
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

struct SearchBarView: View {
    @ObservedObject var manager: FileExplorerManager

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 13))

            TextField("Search files and folders", text: $manager.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))

            if !manager.searchText.isEmpty {
                Button(action: {
                    manager.searchText = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
    }
}

struct TableHeaderView: View {
    var body: some View {
        HStack(spacing: 0) {
            Text("Name")
                .frame(minWidth: 250, alignment: .leading)

            Spacer()

            Text("Modified ago")
                .frame(width: 180, alignment: .leading)

            Text("Size")
                .frame(width: 80, alignment: .trailing)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundColor(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
    }
}

struct FileTableView: View {
    @ObservedObject var manager: FileExplorerManager
    @State private var isDragOver = false

    var body: some View {
        if manager.allItems.isEmpty {
            EmptyFolderView()
                .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
                    handleDrop(providers: providers)
                    return true
                }
        } else if manager.filteredItems.isEmpty {
            EmptySearchResultsView(searchText: manager.searchText)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(manager.filteredItems.enumerated()), id: \.element.id) { index, fileInfo in
                            let actualIndex = manager.allItems.firstIndex(where: { $0.url == fileInfo.url }) ?? -1
                            FileTableRow(fileInfo: fileInfo, manager: manager, index: actualIndex)
                                .id(fileInfo.id)
                        }
                    }
                }
                .id(manager.currentPath.absoluteString)
                .onChange(of: manager.selectedIndex) { newIndex in
                    if newIndex >= 0 {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isDragOver ? Color.accentColor : Color.clear, lineWidth: 3)
                        .allowsHitTesting(false)
                )
                .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
                    handleDrop(providers: providers)
                    return true
                }
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        let currentPath = manager.currentPath

        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, error in
                guard let data = data as? Data,
                      let sourceURL = URL(dataRepresentation: data, relativeTo: nil) else { return }

                let destinationURL = currentPath.appendingPathComponent(sourceURL.lastPathComponent)

                // Don't copy if source is same as destination
                guard sourceURL.deletingLastPathComponent().path != currentPath.path else { return }

                let destURL = destinationURL
                let srcURL = sourceURL
                let curPath = currentPath
                Task.detached {
                    do {
                        var finalURL = destURL
                        var counter = 1
                        while FileManager.default.fileExists(atPath: finalURL.path) {
                            let baseName = destURL.deletingPathExtension().lastPathComponent
                            let ext = destURL.pathExtension
                            let newName = ext.isEmpty ? "\(baseName) \(counter)" : "\(baseName) \(counter).\(ext)"
                            finalURL = curPath.appendingPathComponent(newName)
                            counter += 1
                        }

                        try FileManager.default.copyItem(at: srcURL, to: finalURL)
                        await MainActor.run {
                            self.manager.refresh()
                            ToastManager.shared.show("Copied \(srcURL.lastPathComponent)")
                        }
                    } catch {
                        await MainActor.run {
                            ToastManager.shared.show("Drop error: \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
    }
}

struct FileTableRow: View {
    let fileInfo: CachedFileInfo
    @ObservedObject var manager: FileExplorerManager
    @ObservedObject var selection = SelectionManager.shared
    let index: Int
    @State private var isHovered = false
    @State private var showingDetails = false
    @FocusState private var isRenameFieldFocused: Bool

    private var url: URL { fileInfo.url }

    private var isDirectory: Bool { fileInfo.isDirectory }

    private var isSelected: Bool {
        manager.selectedIndex == index && manager.selectedItem == url
    }

    private var isInSelection: Bool {
        let _ = selection.version
        return selection.items.contains { $0.localURL == url }
    }

    private var isHidden: Bool { fileInfo.isHidden }

    private var isRenaming: Bool {
        manager.renamingItem == url
    }

    private var isAppBundle: Bool {
        url.pathExtension.lowercased() == "app"
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 10) {
                // Use actual app icon for .app bundles, SF Symbol for others
                if isAppBundle {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable()
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: iconForItem)
                        .font(.system(size: 18))
                        .foregroundColor(iconColor)
                        .frame(width: 24)
                }

                if isRenaming {
                    RenameTextField(text: $manager.renameText, onCommit: {
                        manager.confirmRename()
                    }, onCancel: {
                        manager.cancelRename()
                    })
                    .frame(height: 18)
                } else {
                    Text(url.lastPathComponent)
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .foregroundColor(isSelected ? .white : .primary)
                }
            }
            .frame(minWidth: 250, alignment: .leading)

            Spacer()

            Text(humanReadableDate)
                .font(.system(size: 12))
                .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                .frame(width: 180, alignment: .leading)

            Text(fileSizeDisplay)
                .font(.system(size: 12))
                .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            isSelected ? Color.accentColor :
            (isInSelection ? Color.green.opacity(0.15) :
            (isHovered ? Color(NSColor.selectedContentBackgroundColor).opacity(0.2) : Color.clear))
        )
        .cornerRadius(4)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .onAppear { }
        .gesture(TapGesture(count: 2).onEnded {
            // Double-click: folder enters, file adds to selection
            if isDirectory {
                manager.navigateTo(url)
            } else {
                manager.addFileToSelection(url)
            }
        })
        .simultaneousGesture(TapGesture(count: 1).onEnded {
            // Single click: select/toggle for both folders and files
            if manager.selectedItem == url {
                manager.selectedItem = nil
                manager.selectedIndex = -1
            } else {
                manager.selectItem(at: index, url: url)
            }
        })
        .onDrag {
            NSItemProvider(object: url as NSURL)
        }
        .opacity(isHidden ? 0.5 : 1.0)
        .contextMenu {
            Button(action: {
                showingDetails = true
            }) {
                Label("View Details", systemImage: "info.circle")
            }

            Button(action: {
                manager.addFileToSelection(url)
            }) {
                Label("Add to Selection", systemImage: "checkmark.circle")
            }

            Divider()

            Button(action: {
                manager.duplicateFile(url)
            }) {
                Label("Duplicate", systemImage: "doc.on.doc")
            }

            Button(action: {
                manager.addToZip(url)
            }) {
                Label("Add to Zip", systemImage: "doc.zipper")
            }

            Divider()

            Button(role: .destructive, action: {
                manager.moveToTrash(url)
            }) {
                Label("Move to Trash", systemImage: "trash")
            }
        }
        .sheet(isPresented: $showingDetails) {
            FileDetailsView(url: url, isDirectory: isDirectory)
        }
    }

    private var iconForItem: String {
        if isDirectory {
            return "folder.fill"
        }
        switch url.pathExtension.lowercased() {
        // Images
        case "jpg", "jpeg", "png", "gif", "bmp", "webp", "heic", "tiff", "svg", "ico", "raw":
            return "photo.fill"
        // PDF
        case "pdf":
            return "doc.text.fill"
        // Documents
        case "txt", "rtf":
            return "doc.plaintext.fill"
        case "md", "markdown":
            return "text.document.fill"
        case "doc", "docx", "odt":
            return "doc.richtext.fill"
        case "pages":
            return "doc.richtext.fill"
        // Spreadsheets
        case "xls", "xlsx", "csv", "numbers", "ods":
            return "tablecells.fill"
        // Presentations
        case "ppt", "pptx", "key", "odp":
            return "slider.horizontal.below.rectangle"
        // Archives
        case "zip", "tar", "gz", "rar", "7z", "bz2", "xz", "dmg", "iso":
            return "doc.zipper"
        // Audio
        case "mp3", "wav", "m4a", "aac", "flac", "ogg", "wma", "aiff":
            return "waveform"
        // Video
        case "mp4", "mov", "avi", "mkv", "webm", "wmv", "flv", "m4v":
            return "film.fill"
        // Code
        case "swift":
            return "swift"
        case "py":
            return "chevron.left.forwardslash.chevron.right"
        case "js", "ts", "jsx", "tsx":
            return "chevron.left.forwardslash.chevron.right"
        case "c", "cpp", "h", "hpp", "m", "mm":
            return "chevron.left.forwardslash.chevron.right"
        case "java", "kt", "scala":
            return "chevron.left.forwardslash.chevron.right"
        case "rb", "php", "pl":
            return "chevron.left.forwardslash.chevron.right"
        case "go", "rs", "zig":
            return "chevron.left.forwardslash.chevron.right"
        case "sh", "bash", "zsh", "fish":
            return "terminal.fill"
        // Web/Config
        case "html", "htm":
            return "globe"
        case "css", "scss", "sass", "less":
            return "paintbrush.fill"
        case "json", "xml", "yaml", "yml", "toml", "ini", "conf", "config":
            return "gearshape.fill"
        case "sql", "db", "sqlite":
            return "cylinder.fill"
        // Fonts
        case "ttf", "otf", "woff", "woff2":
            return "textformat"
        // Executables
        case "app", "exe", "bin":
            return "app.fill"
        case "pkg", "deb", "rpm":
            return "shippingbox.fill"
        // Design
        case "psd", "ai", "sketch", "fig", "xd":
            return "paintpalette.fill"
        // 3D
        case "obj", "fbx", "blend", "3ds", "dae":
            return "cube.fill"
        default:
            return "doc.fill"
        }
    }

    private var iconColor: Color {
        if isDirectory {
            return Color(red: 0.35, green: 0.67, blue: 0.95) // macOS folder blue
        }
        switch url.pathExtension.lowercased() {
        // Images - purple/magenta
        case "jpg", "jpeg", "png", "gif", "bmp", "webp", "heic", "tiff", "svg", "ico", "raw":
            return Color(red: 0.69, green: 0.42, blue: 0.87)
        // PDF - red
        case "pdf":
            return Color(red: 0.92, green: 0.26, blue: 0.24)
        // Documents - blue
        case "doc", "docx", "odt", "pages", "txt", "rtf", "md", "markdown":
            return Color(red: 0.26, green: 0.52, blue: 0.96)
        // Spreadsheets - green
        case "xls", "xlsx", "csv", "numbers", "ods":
            return Color(red: 0.21, green: 0.71, blue: 0.35)
        // Presentations - orange
        case "ppt", "pptx", "key", "odp":
            return Color(red: 0.96, green: 0.58, blue: 0.12)
        // Archives - brown
        case "zip", "tar", "gz", "rar", "7z", "bz2", "xz", "dmg", "iso":
            return Color(red: 0.6, green: 0.5, blue: 0.4)
        // Audio - pink
        case "mp3", "wav", "m4a", "aac", "flac", "ogg", "wma", "aiff":
            return Color(red: 0.95, green: 0.35, blue: 0.55)
        // Video - orange/red
        case "mp4", "mov", "avi", "mkv", "webm", "wmv", "flv", "m4v":
            return Color(red: 0.96, green: 0.42, blue: 0.32)
        // Code - cyan/teal
        case "swift", "py", "js", "ts", "jsx", "tsx", "c", "cpp", "h", "hpp", "m", "mm",
             "java", "kt", "scala", "rb", "php", "pl", "go", "rs", "zig", "sh", "bash", "zsh", "fish":
            return Color(red: 0.2, green: 0.75, blue: 0.75)
        // Web - blue
        case "html", "htm":
            return Color(red: 0.9, green: 0.45, blue: 0.2)
        case "css", "scss", "sass", "less":
            return Color(red: 0.26, green: 0.52, blue: 0.96)
        // Config - gray
        case "json", "xml", "yaml", "yml", "toml", "ini", "conf", "config":
            return Color(red: 0.55, green: 0.55, blue: 0.58)
        // Database - purple
        case "sql", "db", "sqlite":
            return Color(red: 0.55, green: 0.35, blue: 0.75)
        // Design - pink/magenta
        case "psd", "ai", "sketch", "fig", "xd":
            return Color(red: 0.85, green: 0.25, blue: 0.55)
        default:
            return .secondary
        }
    }

    private var humanReadableDate: String {
        guard let date = fileInfo.modDate else { return "" }

        let now = Date()
        let interval = now.timeIntervalSince(date)

        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let mins = Int(interval / 60)
            return "\(mins) minute\(mins == 1 ? "" : "s")"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            let mins = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)
            if mins > 0 {
                return "\(hours) hour\(hours == 1 ? "" : "s") & \(mins) min"
            }
            return "\(hours) hour\(hours == 1 ? "" : "s")"
        } else if interval < 86400 * 30 {
            let days = Int(interval / 86400)
            let hours = Int((interval.truncatingRemainder(dividingBy: 86400)) / 3600)
            if hours > 0 && days < 7 {
                return "\(days) day\(days == 1 ? "" : "s") & \(hours) hour\(hours == 1 ? "" : "s")"
            }
            return "\(days) day\(days == 1 ? "" : "s")"
        } else if interval < 86400 * 365 {
            let months = Int(interval / (86400 * 30))
            let days = Int((interval.truncatingRemainder(dividingBy: 86400 * 30)) / 86400)
            if days > 0 && months < 6 {
                return "\(months) month\(months == 1 ? "" : "s") & \(days) day\(days == 1 ? "" : "s")"
            }
            return "\(months) month\(months == 1 ? "" : "s")"
        } else {
            let years = Int(interval / (86400 * 365))
            let months = Int((interval.truncatingRemainder(dividingBy: 86400 * 365)) / (86400 * 30))
            if months > 0 {
                return "\(years) year\(years == 1 ? "" : "s") & \(months) month\(months == 1 ? "" : "s")"
            }
            return "\(years) year\(years == 1 ? "" : "s")"
        }
    }

    private var fileSizeDisplay: String {
        if isDirectory { return "--" }
        return ByteCountFormatter.string(fromByteCount: fileInfo.size, countStyle: .file)
    }
}

struct FileDetailsView: View {
    let url: URL
    let isDirectory: Bool
    @Environment(\.dismiss) var dismiss
    @State private var fileSize: String = "Calculating..."
    @State private var itemCount: Int? = nil
    @State private var cachedAttributes: [FileAttributeKey: Any]?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: isDirectory ? "folder.fill" : "doc.fill")
                    .font(.system(size: 32))
                    .foregroundColor(isDirectory ? Color(red: 0.35, green: 0.67, blue: 0.95) : .secondary)

                Text(url.lastPathComponent)
                    .font(.system(size: 18, weight: .semibold))
                    .lineLimit(2)

                Spacer()
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                DetailRow(label: "Kind", value: isDirectory ? "Folder" : fileKind)
                DetailRow(label: "Size", value: fileSize)
                if let count = itemCount {
                    DetailRow(label: "Contains", value: "\(count) items")
                }
                DetailRow(label: "Location", value: url.deletingLastPathComponent().path)
                if let created = cachedAttributes?[.creationDate] as? Date {
                    DetailRow(label: "Created", value: formatDate(created))
                }
                if let modified = cachedAttributes?[.modificationDate] as? Date {
                    DetailRow(label: "Modified", value: formatDate(modified))
                }
                if let permissions = cachedAttributes?[.posixPermissions] as? Int {
                    DetailRow(label: "Permissions", value: String(format: "%o", permissions))
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 400, height: 350)
        .onAppear {
            cachedAttributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            calculateSize()
        }
    }

    private var fileKind: String {
        let ext = url.pathExtension.lowercased()
        if ext.isEmpty { return "File" }
        return "\(ext.uppercased()) file"
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func calculateSize() {
        DispatchQueue.global(qos: .userInitiated).async {
            if isDirectory {
                var totalSize: UInt64 = 0
                var count = 0
                if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: []) {
                    for case let fileURL as URL in enumerator {
                        count += 1
                        if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                            totalSize += UInt64(size)
                        }
                    }
                }
                let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(totalSize), countStyle: .file)
                DispatchQueue.main.async {
                    fileSize = sizeStr
                    itemCount = count
                }
            } else {
                if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                   let size = attrs[.size] as? UInt64 {
                    let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
                    DispatchQueue.main.async {
                        fileSize = sizeStr
                    }
                }
            }
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .trailing)

            Text(value)
                .font(.system(size: 13))
                .textSelection(.enabled)

            Spacer()
        }
    }
}

struct EmptyFolderView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("This folder is empty")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptySearchResultsView: View {
    let searchText: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No results for \"\(searchText)\"")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct RenameTextField: NSViewRepresentable {
    @Binding var text: String
    var onCommit: () -> Void
    var onCancel: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.delegate = context.coordinator
        textField.font = NSFont.systemFont(ofSize: 13)
        textField.isBordered = false
        textField.drawsBackground = true
        textField.backgroundColor = NSColor.textBackgroundColor
        textField.focusRingType = .none
        textField.cell?.usesSingleLineMode = true
        textField.cell?.wraps = false
        textField.cell?.isScrollable = true
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }

        // Focus and select text on first appearance
        if !context.coordinator.didFocus {
            context.coordinator.didFocus = true
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
                // Select filename without extension
                if let ext = text.split(separator: ".").last, text.contains(".") && ext.count < text.count - 1 {
                    let nameLength = text.count - ext.count - 1
                    nsView.currentEditor()?.selectedRange = NSRange(location: 0, length: nameLength)
                } else {
                    nsView.selectText(nil)
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: RenameTextField
        var didFocus = false

        init(_ parent: RenameTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                parent.text = textField.stringValue
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onCommit()
                return true
            } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onCancel()
                return true
            }
            return false
        }
    }
}
