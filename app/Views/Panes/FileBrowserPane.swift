import SwiftUI

struct FileBrowserPane: View {
    @ObservedObject var manager: FileExplorerManager

    var body: some View {
        VStack(spacing: 0) {
            SelectionBar(manager: manager)

            ActionButtonBar(manager: manager)
            Divider()

            if manager.isSearching {
                SearchBar(manager: manager)
                Divider()
                SearchResultsView(manager: manager)
            } else {
                FileTreeView(manager: manager)
            }
        }
    }
}

// MARK: - Search Bar

struct SearchBar: View {
    @ObservedObject var manager: FileExplorerManager

    private var displayPath: String {
        let path = manager.currentPath.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Search in \(displayPath)")
                .textStyle(.small)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 10) {
                SearchTextField(text: Binding(
                    get: { manager.searchQuery },
                    set: { manager.performSearch($0) }
                ), onCancel: { manager.cancelSearch() })
                .frame(height: 36)

                if manager.isSearchRunning {
                    ProgressView()
                        .controlSize(.small)
                }

                if !manager.searchQuery.isEmpty {
                    Text("\(manager.searchResults.count)")
                        .textStyle(.buttons)
                        .foregroundColor(.secondary)
                }

                Button(action: { manager.cancelSearch() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
}

// MARK: - Search Results View

struct SearchResultsView: View {
    @ObservedObject var manager: FileExplorerManager

    private static let home = FileManager.default.homeDirectoryForCurrentUser

    private func relativePath(_ url: URL) -> String {
        let full = url.path
        let base = manager.currentPath.path
        if full.hasPrefix(base) {
            let rel = String(full.dropFirst(base.count))
            return rel.hasPrefix("/") ? String(rel.dropFirst()) : rel
        }
        return full
    }

    var body: some View {
        if manager.searchResults.isEmpty && !manager.isSearchRunning {
            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 32))
                    .foregroundColor(.secondary)
                if manager.searchQuery.isEmpty {
                    Text("Type to search files")
                        .textStyle(.buttons)
                        .foregroundColor(.secondary)
                } else {
                    Text("No results for \"\(manager.searchQuery)\"")
                        .textStyle(.buttons)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(manager.searchResults.enumerated()), id: \.element.id) { index, item in
                        SearchResultRow(
                            item: item,
                            index: index,
                            manager: manager
                        )
                    }
                }
            }
        }
    }
}

struct SearchResultRow: View {
    let item: CachedFileInfo
    let index: Int
    @ObservedObject var manager: FileExplorerManager

    private var parentPath: String {
        let parent = item.url.deletingLastPathComponent().path
        let base = manager.currentPath.path
        if parent == base { return "" }
        if parent.hasPrefix(base) {
            let rel = String(parent.dropFirst(base.count))
            return rel.hasPrefix("/") ? String(rel.dropFirst()) : rel
        }
        return parent
    }

    var body: some View {
        FileListRow(
            url: item.url,
            isDirectory: item.isDirectory,
            exists: true,
            parentPath: parentPath,
            isSelected: manager.selectedItem == item.url
        )
        .onTapGesture {
            manager.listCursorIndex = index
            manager.selectItem(at: -1, url: item.url)
        }
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
                            .textStyle(.small, weight: .semibold)
                            .foregroundColor(.secondary)
                            .frame(width: 16)
                    }
                    .buttonStyle(.plain)

                    Text("SELECTION (\(selectedItems.count))")
                        .textStyle(.small, weight: .semibold)
                        .foregroundColor(.secondary)

                    Spacer()

                    // Action buttons always visible
                    if !localItems.isEmpty {
                        SelectionBarButton(title: "Paste here", icon: "doc.on.doc", color: .blue) {
                            let count = selection.copyLocalItems(to: manager.currentPath)
                            selection.clear()
                            ToastManager.shared.show("Pasted \(count) file(s)")
                            manager.refresh()
                        }
                        SelectionBarButton(title: "Move here", icon: "folder", color: .orange) {
                            let count = selection.moveLocalItems(to: manager.currentPath)
                            ToastManager.shared.show("Moved \(count) file(s)")
                            manager.refresh()
                        }
                        SelectionBarButton(title: "Trash", icon: "trash", color: .red) {
                            var failed = 0
                            for item in localItems {
                                if let url = item.localURL {
                                    do {
                                        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                                    } catch {
                                        failed += 1
                                    }
                                }
                                selection.remove(item)
                            }
                            if failed > 0 {
                                ToastManager.shared.showError("Failed to trash \(failed) file(s)")
                            } else {
                                ToastManager.shared.show("Moved \(localItems.count) file(s) to Trash")
                            }
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
                            .textStyle(.default)
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
                    .textStyle(.small)
                Text(title)
                    .textStyle(.small, weight: .medium)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
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
                .textStyle(.small)
                .foregroundColor(iconColor)

            Text(item.name)
                .textStyle(.small)
                .lineLimit(1)

            Button(action: { selection.remove(item) }) {
                Image(systemName: "xmark")
                    .textStyle(.small, weight: .bold)
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
                    .textStyle(.small)
                    .foregroundColor(.secondary)
                Spacer()
                if !selectedItems.isEmpty {
                    Button(action: { selection.clear() }) {
                        Text("Clear All")
                            .textStyle(.small)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
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
                        .textStyle(.buttons)
                        .foregroundColor(.secondary)
                    Text("Press Space on a file to add it to selection")
                        .textStyle(.small)
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Action buttons
                VStack(spacing: 8) {
                    if !localItems.isEmpty {
                        HStack(spacing: 8) {
                            Text("Local (\(localItems.count)):")
                                .textStyle(.small)
                                .foregroundColor(.secondary)
                            SelectionActionButton(title: "Paste here", icon: "doc.on.doc", color: .blue) {
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
                                .textStyle(.small)
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
            Text({
                let action = isPermanentDelete ? "permanently delete" : "move to trash"
                let suffix = localItems.count == 1 ? "" : "s"
                let warning = isPermanentDelete ? " This cannot be undone." : ""
                return "Are you sure you want to \(action) \(localItems.count) file\(suffix)?\(warning)"
            }())
        }
    }

    private func copyLocalFilesHere() {
        let count = selection.copyLocalItems(to: manager.currentPath)
        selection.clear()
        ToastManager.shared.show("Pasted \(count) file(s)")
        manager.refresh()
    }

    private func moveLocalFilesHere() {
        let count = selection.moveLocalItems(to: manager.currentPath)
        ToastManager.shared.show("Moved \(count) file(s)")
        manager.refresh()
    }

    private func trashLocalFiles() {
        var failed = 0
        for item in localItems {
            if let url = item.localURL {
                do {
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                } catch {
                    failed += 1
                }
                selection.remove(item)
            }
        }
        if failed > 0 {
            ToastManager.shared.showError("Failed to trash \(failed) file(s)")
        }
        manager.refresh()
    }

    private func permanentDeleteLocalFiles() {
        var failed = 0
        for item in localItems {
            if let url = item.localURL {
                do {
                    try FileManager.default.removeItem(at: url)
                } catch {
                    failed += 1
                }
                selection.remove(item)
            }
        }
        if failed > 0 {
            ToastManager.shared.showError("Failed to delete \(failed) file(s)")
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
                    .textStyle(.small)
                Text(title)
                    .textStyle(.default, weight: .medium)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
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
                .textStyle(.buttons)
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
