import SwiftUI
import WebKit

struct FileBrowserPane: View {
    @ObservedObject var manager: FileExplorerManager
    @ObservedObject private var settings = AppSettings.shared

    // Preview URL: selected file only
    private var previewURL: URL? {
        if let selected = manager.selectedItem {
            // Check if it's previewable
            if PreviewType.detect(for: selected) != .none {
                return selected
            }
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            ViewModeSelector(manager: manager)
            Divider()
            BreadcrumbView(manager: manager)
            Divider()

            // Selection bar - always visible when there are selected items
            SelectionBar(manager: manager)

            ActionButtonBar(manager: manager)
            Divider()

            switch manager.browserViewMode {
            case .files, .selected:
                filesView
            case .gallery:
                galleryView
            case .search:
                searchView
            }
        }
    }

    @ViewBuilder
    private var filesView: some View {
        if manager.allItems.count > 20 {
            SearchBarView(manager: manager)
            Divider()
        }

        TableHeaderView()
        Divider()

        if settings.showPreviewPane, let previewURL = previewURL {
            ResizableSplitView(
                top: { FileTableView(manager: manager) },
                bottom: { PreviewPane(url: previewURL) }
            )
        } else {
            FileTableView(manager: manager)
        }
    }

    @ViewBuilder
    private var galleryView: some View {
        GalleryView(manager: manager)
    }

    @ViewBuilder
    private var searchView: some View {
        if settings.showPreviewPane, let previewURL = previewURL {
            ResizableSplitView(
                top: { RecursiveSearchView(manager: manager) },
                bottom: { PreviewPane(url: previewURL) }
            )
        } else {
            RecursiveSearchView(manager: manager)
        }
    }


}

struct ViewModeSelector: View {
    @ObservedObject var manager: FileExplorerManager

    @ObservedObject private var selection = SelectionManager.shared

    private var selectionCount: Int {
        // Reference version to trigger updates
        let _ = selection.version
        return selection.count
    }

    // Filter out "Selected" tab since selection is now shown in SelectionBar
    private var visibleModes: [BrowserViewMode] {
        BrowserViewMode.allCases.filter { $0 != .selected }
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(visibleModes, id: \.self) { mode in
                let isSelected = manager.browserViewMode == mode
                Text(mode.rawValue)
                    .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                    .foregroundColor(isSelected ? .white : .secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isSelected ? Color.accentColor : Color.clear)
                    )
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { _ in
                                manager.browserViewMode = mode
                            }
                    )
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
}

// MARK: - Selection Bar (shown below breadcrumb when items selected)

struct SelectionBar: View {
    @ObservedObject var manager: FileExplorerManager
    @ObservedObject var selection = SelectionManager.shared
    @State private var isExpanded = true

    private var selectedItems: [FileItem] {
        let _ = selection.version
        return Array(selection.items).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private var localItems: [FileItem] {
        selectedItems.filter { if case .local = $0.source { return true } else { return false } }
    }

    private var iPhoneItems: [FileItem] {
        selectedItems.filter { if case .iPhone = $0.source { return true } else { return false } }
    }

    var body: some View {
        if !selectedItems.isEmpty {
            VStack(spacing: 0) {
                // Header row
                HStack(spacing: 8) {
                    Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 16)
                    }
                    .buttonStyle(.plain)

                    Text("SELECTION (\(selectedItems.count))")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)

                    Spacer()

                    // Action buttons always visible
                    if !localItems.isEmpty {
                        SelectionBarButton(title: "Copy here", icon: "doc.on.doc", color: .blue) {
                            let count = selection.copyLocalItems(to: manager.currentPath)
                            ToastManager.shared.show("Copied \(count) file(s)")
                            manager.refresh()
                        }
                        SelectionBarButton(title: "Move here", icon: "folder", color: .orange) {
                            let count = selection.moveLocalItems(to: manager.currentPath)
                            ToastManager.shared.show("Moved \(count) file(s)")
                            manager.refresh()
                        }
                        SelectionBarButton(title: "Trash", icon: "trash", color: .red) {
                            for item in localItems {
                                if let url = item.localURL {
                                    try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
                                }
                                selection.remove(item)
                            }
                            ToastManager.shared.show("Moved \(localItems.count) file(s) to Trash")
                            manager.refresh()
                        }
                    }

                    if !iPhoneItems.isEmpty {
                        SelectionBarButton(title: "Download", icon: "arrow.down.doc", color: .pink) {
                            Task {
                                let count = await selection.downloadIPhoneItems(to: manager.currentPath, move: false)
                                ToastManager.shared.show("Downloaded \(count) file(s)")
                                for item in iPhoneItems { selection.remove(item) }
                                manager.refresh()
                            }
                        }
                    }

                    Button(action: { selection.clear() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear selection")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.green.opacity(0.08))

                // Expanded file list
                if isExpanded {
                    Divider()
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(selectedItems, id: \.id) { item in
                                SelectionBarItem(item: item, selection: selection)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                    .background(Color.green.opacity(0.05))
                }

                Divider()
            }
        }
    }
}

struct SelectionBarButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .foregroundColor(color)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
}

struct SelectionBarItem: View {
    let item: FileItem
    @ObservedObject var selection: SelectionManager
    @State private var isHovered = false

    private var iconName: String {
        switch item.source {
        case .local:
            return item.isDirectory ? "folder.fill" : "doc.fill"
        case .iPhone:
            return "iphone"
        }
    }

    private var iconColor: Color {
        switch item.source {
        case .local:
            return item.isDirectory ? .blue : .secondary
        case .iPhone:
            return .pink
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.system(size: 10))
                .foregroundColor(iconColor)

            Text(item.name)
                .font(.system(size: 12))
                .lineLimit(1)

            Button(action: { selection.remove(item) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0.5)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.green.opacity(0.3), lineWidth: 1)
        )
        .onHover { isHovered = $0 }
    }
}

struct GalleryView: NSViewRepresentable {
    @ObservedObject var manager: FileExplorerManager

    nonisolated private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "bmp", "webp", "heic", "heif", "tiff", "tif"]

    class Coordinator: NSObject, WKScriptMessageHandler {
        var parent: GalleryView
        var imageURLs: [URL] = []
        var lastLoadedPath: String = ""
        var isLoading = false

        init(_ parent: GalleryView) {
            self.parent = parent
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "imageClick", let index = message.body as? Int {
                if index >= 0 && index < imageURLs.count {
                    let url = imageURLs[index]
                    Task { @MainActor in
                        self.parent.manager.selectItem(at: -1, url: url)
                    }
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.userContentController.add(context.coordinator, name: "imageClick")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let currentPath = manager.currentPath.path
        guard currentPath != context.coordinator.lastLoadedPath, !context.coordinator.isLoading else { return }
        context.coordinator.lastLoadedPath = currentPath
        context.coordinator.isLoading = true

        let dirURL = manager.currentPath

        // Load gallery HTML off main thread
        Task.detached {
            let images = Self.findImages(in: dirURL)
            let html = Self.generateGalleryHTML(images: images)

            await MainActor.run {
                context.coordinator.imageURLs = images
                context.coordinator.isLoading = false
                webView.loadHTMLString(html, baseURL: dirURL)
            }
        }
    }

    nonisolated private static func findImages(in directory: URL) -> [URL] {
        var images: [URL] = []
        let fm = FileManager.default

        guard let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        for fileURL in contents {
            let ext = fileURL.pathExtension.lowercased()
            if imageExtensions.contains(ext) {
                images.append(fileURL)
                if images.count >= 500 { break }
            }
        }

        return images.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }

    nonisolated private static func resizeAndEncodeImage(_ url: URL) -> String? {
        guard let image = NSImage(contentsOf: url) else { return nil }

        let maxSize: CGFloat = 200
        let originalSize = image.size
        var newSize = originalSize

        if originalSize.width > maxSize || originalSize.height > maxSize {
            let widthRatio = maxSize / originalSize.width
            let heightRatio = maxSize / originalSize.height
            let ratio = min(widthRatio, heightRatio)
            newSize = NSSize(width: originalSize.width * ratio, height: originalSize.height * ratio)
        }

        let resizedImage = NSImage(size: newSize)
        resizedImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: originalSize),
                   operation: .copy,
                   fraction: 1.0)
        resizedImage.unlockFocus()

        guard let tiffData = resizedImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            return nil
        }

        return jpegData.base64EncodedString()
    }

    nonisolated private static func generateGalleryHTML(images: [URL]) -> String {
        var imageElements = ""
        for (index, url) in images.enumerated() {
            // Use file:// URLs instead of base64 to avoid loading all images into memory
            let filename = url.lastPathComponent
            let escapedPath = url.absoluteString
            imageElements += """
            <div class="item" onclick="window.webkit.messageHandlers.imageClick.postMessage(\(index))">
                <img src="\(escapedPath)" loading="lazy" alt="\(filename)" title="\(filename)">
                <div class="name">\(filename)</div>
            </div>
            """
        }

        if imageElements.isEmpty {
            imageElements = """
            <div class="empty">
                <div class="icon">&#128444;</div>
                <div>No images found</div>
            </div>
            """
        }

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                body {
                    font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                    background: transparent;
                    padding: 16px;
                }
                .gallery {
                    display: flex;
                    flex-wrap: wrap;
                    gap: 12px;
                }
                .item {
                    width: 200px;
                    text-align: center;
                    cursor: pointer;
                    padding: 8px;
                    border-radius: 8px;
                    transition: background 0.15s;
                }
                .item:hover {
                    background: rgba(128, 128, 128, 0.15);
                }
                .item.selected {
                    background: rgba(0, 122, 255, 0.2);
                }
                .item img {
                    max-width: 200px;
                    max-height: 200px;
                    border-radius: 4px;
                    box-shadow: 0 2px 8px rgba(0,0,0,0.1);
                    object-fit: contain;
                }
                .item .name {
                    margin-top: 6px;
                    font-size: 11px;
                    color: #666;
                    overflow: hidden;
                    text-overflow: ellipsis;
                    white-space: nowrap;
                }
                .empty {
                    width: 100%;
                    text-align: center;
                    padding: 60px 20px;
                    color: #888;
                    font-size: 14px;
                }
                .empty .icon {
                    font-size: 48px;
                    margin-bottom: 12px;
                }
                @media (prefers-color-scheme: dark) {
                    .item .name { color: #aaa; }
                    .empty { color: #888; }
                }
            </style>
        </head>
        <body>
            <div class="gallery">
                \(imageElements)
            </div>
        </body>
        </html>
        """
    }
}

struct RecursiveSearchView: View {
    @ObservedObject var manager: FileExplorerManager
    @State private var searchQuery: String = ""
    @State private var searchResults: [URL] = []
    @State private var isSearching: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search recursively in \(manager.currentPath.lastPathComponent)...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        performSearch()
                    }
                if isSearching {
                    ProgressView()
                        .scaleEffect(0.7)
                }
                if !searchQuery.isEmpty {
                    Button(action: {
                        searchQuery = ""
                        searchResults = []
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            if searchResults.isEmpty && !searchQuery.isEmpty && !isSearching {
                VStack {
                    Spacer()
                    Text("No results found")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List(searchResults, id: \.self, selection: $manager.selectedItem) { url in
                    HStack(spacing: 8) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                            .resizable()
                            .frame(width: 16, height: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(url.lastPathComponent)
                                .font(.system(size: 13))
                            Text(url.deletingLastPathComponent().path.replacingOccurrences(of: manager.currentPath.path, with: "."))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        manager.openItem(url)
                    }
                    .onTapGesture {
                        manager.selectItem(at: -1, url: url)
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(Color(NSColor.textBackgroundColor))
    }

    private func performSearch() {
        guard !searchQuery.isEmpty else { return }
        isSearching = true
        searchResults = []

        let query = searchQuery
        let directory = manager.currentPath

        DispatchQueue.global(qos: .userInitiated).async {
            var results: [URL] = []
            let fm = FileManager.default
            let lowercaseQuery = query.lowercased()

            if let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
                for case let fileURL as URL in enumerator {
                    if fileURL.lastPathComponent.lowercased().contains(lowercaseQuery) {
                        results.append(fileURL)
                        if results.count >= 500 { break }
                    }
                }
            }

            let sorted = results.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }

            DispatchQueue.main.async {
                self.searchResults = sorted
                self.isSearching = false
            }
        }
    }
}

struct SelectedFilesView: View {
    @ObservedObject var manager: FileExplorerManager
    @ObservedObject var selection = SelectionManager.shared
    @State private var showDeleteConfirmation = false
    @State private var isPermanentDelete = false

    private var selectedItems: [FileItem] {
        let _ = selection.version
        return Array(selection.items).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private var localItems: [FileItem] {
        selectedItems.filter { if case .local = $0.source { return true } else { return false } }
    }

    private var iPhoneItems: [FileItem] {
        selectedItems.filter { if case .iPhone = $0.source { return true } else { return false } }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with clear all button
            HStack {
                Text("\(selectedItems.count) item\(selectedItems.count == 1 ? "" : "s") selected")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
                if !selectedItems.isEmpty {
                    Text("Clear All")
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onEnded { _ in
                                    selection.clear()
                                }
                        )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            if selectedItems.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "square.dashed")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("No files selected")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Text("Press Space on a file to add it to selection")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Action buttons
                VStack(spacing: 8) {
                    if !localItems.isEmpty {
                        HStack(spacing: 8) {
                            Text("Local (\(localItems.count)):")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            SelectionActionButton(title: "Copy here", icon: "doc.on.doc", color: .blue) {
                                copyLocalFilesHere()
                            }
                            SelectionActionButton(title: "Move here", icon: "folder", color: .orange) {
                                moveLocalFilesHere()
                            }
                            SelectionActionButton(title: "Trash", icon: "trash", color: .red) {
                                isPermanentDelete = false
                                showDeleteConfirmation = true
                            }
                            Spacer()
                        }
                    }

                    if !iPhoneItems.isEmpty {
                        HStack(spacing: 8) {
                            Text("iPhone (\(iPhoneItems.count)):")
                                .font(.system(size: 12))
                                .foregroundColor(.pink)
                            SelectionActionButton(title: "Download here", icon: "arrow.down.doc", color: .blue) {
                                Task { await downloadiPhoneFilesHere() }
                            }
                            SelectionActionButton(title: "Delete", icon: "trash", color: .red) {
                                Task { await deleteiPhoneFiles() }
                            }
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()

                // File list
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(selectedItems, id: \.id) { item in
                            SelectedItemRow(item: item, selection: selection, manager: manager)
                        }
                    }
                }
            }
        }
        .background(Color(NSColor.textBackgroundColor))
        .alert(isPermanentDelete ? "Permanently Delete?" : "Move to Trash?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button(isPermanentDelete ? "Delete" : "Move to Trash", role: .destructive) {
                if isPermanentDelete {
                    permanentDeleteLocalFiles()
                } else {
                    trashLocalFiles()
                }
            }
        } message: {
            Text("Are you sure you want to \(isPermanentDelete ? "permanently delete" : "move to trash") \(localItems.count) file\(localItems.count == 1 ? "" : "s")?\(isPermanentDelete ? " This cannot be undone." : "")")
        }
    }

    private func copyLocalFilesHere() {
        let count = selection.copyLocalItems(to: manager.currentPath)
        ToastManager.shared.show("Copied \(count) file(s)")
        manager.refresh()
    }

    private func moveLocalFilesHere() {
        let count = selection.moveLocalItems(to: manager.currentPath)
        ToastManager.shared.show("Moved \(count) file(s)")
        manager.refresh()
    }

    private func trashLocalFiles() {
        for item in localItems {
            if let url = item.localURL {
                try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
                selection.remove(item)
            }
        }
        manager.refresh()
    }

    private func permanentDeleteLocalFiles() {
        for item in localItems {
            if let url = item.localURL {
                try? FileManager.default.removeItem(at: url)
                selection.remove(item)
            }
        }
        manager.refresh()
    }

    private func downloadiPhoneFilesHere() async {
        let count = await selection.downloadIPhoneItems(to: manager.currentPath, move: false)
        ToastManager.shared.show("Downloaded \(count) file(s)")
        // Clear downloaded items from selection
        for item in iPhoneItems {
            selection.remove(item)
        }
        manager.refresh()
    }

    private func deleteiPhoneFiles() async {
        let count = await selection.deleteAll()
        ToastManager.shared.show("Deleted \(count) file(s)")
    }
}

struct SelectionActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(color.opacity(0.1))
            .foregroundColor(color)
            .cornerRadius(5)
        }
        .buttonStyle(.plain)
    }
}

struct SelectedItemRow: View {
    let item: FileItem
    @ObservedObject var selection: SelectionManager
    @ObservedObject var manager: FileExplorerManager
    @State private var isHovered = false

    private var iconName: String {
        switch item.source {
        case .local:
            return item.isDirectory ? "folder.fill" : "doc.fill"
        case .iPhone:
            return "iphone"
        }
    }

    private var iconColor: Color {
        switch item.source {
        case .local:
            return item.isDirectory ? .blue : .secondary
        case .iPhone:
            return .pink
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .foregroundColor(iconColor)
                .frame(width: 24, height: 24)
            Text(item.displayPath)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.secondary)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { _ in
                            selection.remove(item)
                        }
                )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isHovered ? Color.gray.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onEnded { _ in
                    if let url = item.localURL {
                        manager.selectItem(at: -1, url: url)
                    }
                }
        )
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded {
                    if let url = item.localURL {
                        manager.openItem(url)
                    }
                }
        )
    }
}
