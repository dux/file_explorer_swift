import SwiftUI
import UniformTypeIdentifiers

// MARK: - File Tree View (ancestor path + children)

struct FileTreeView: View {
    @ObservedObject var manager: FileExplorerManager
    @ObservedObject private var settings = AppSettings.shared
    @State private var isDragOver = false

    private static let home = FileManager.default.homeDirectoryForCurrentUser

    private var ancestors: [(name: String, url: URL)] {
        var components: [(String, URL)] = []
        var current = manager.currentPath

        while current.path != "/" && !current.path.isEmpty {
            if current.path == Self.home.path {
                components.insert((current.lastPathComponent, current), at: 0)
                return components
            }
            // Stop at volume mount points (e.g. /Volumes/KINGSTON)
            let parent = current.deletingLastPathComponent()
            if parent.path == "/Volumes" {
                components.insert((current.lastPathComponent, current), at: 0)
                return components
            }
            components.insert((current.lastPathComponent, current), at: 0)
            current = parent
        }
        components.insert(("Root", URL(fileURLWithPath: "/")), at: 0)

        return components
    }

    // Indent per level in points
    private let indentStep: CGFloat = 20

    var body: some View {
        if manager.allItems.isEmpty {
            VStack(spacing: 0) {
                // Show navigation even in empty folders
                LazyVStack(spacing: 0) {
                    Spacer().frame(height: 2)
                    if settings.flatFolders {
                        FlatBreadcrumbRow(ancestors: ancestors, manager: manager)
                    } else {
                        let ancestorList = ancestors
                        ForEach(Array(ancestorList.enumerated()), id: \.element.url) { depth, ancestor in
                            let isCurrent = ancestor.url.path == manager.currentPath.path
                            AncestorRow(
                                name: ancestor.name,
                                url: ancestor.url,
                                depth: depth,
                                isCurrent: isCurrent,
                                indentStep: indentStep,
                                manager: manager
                            )
                        }
                    }
                    let childIndent = settings.flatFolders ? 1 : ancestors.count
                    Text("Folder is empty")
                        .textStyle(.small)
                        .foregroundColor(.secondary)
                        .padding(.leading, CGFloat(childIndent) * indentStep + 16)
                        .padding(.top, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer()
            }
            .folderBackgroundContextMenu(url: manager.currentPath)
            .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
                handleDrop(providers: providers)
                return true
            }
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        Spacer().frame(height: 2)

                        if settings.flatFolders {
                            // Compact breadcrumb + flat list
                            FlatBreadcrumbRow(ancestors: ancestors, manager: manager)

                            ForEach(Array(manager.allItems.enumerated()), id: \.element.id) { index, fileInfo in
                                FileTreeRow(
                                    fileInfo: fileInfo,
                                    manager: manager,
                                    index: index,
                                    depth: 1,
                                    indentStep: indentStep
                                )
                                .id(fileInfo.id)
                            }
                        } else {
                            // Ancestor rows
                            let ancestorList = ancestors
                            ForEach(Array(ancestorList.enumerated()), id: \.element.url) { depth, ancestor in
                                let isCurrent = ancestor.url.path == manager.currentPath.path
                                AncestorRow(
                                    name: ancestor.name,
                                    url: ancestor.url,
                                    depth: depth,
                                    isCurrent: isCurrent,
                                    indentStep: indentStep,
                                    manager: manager
                                )
                            }

                            // Children rows
                            let childDepth = ancestorList.count
                            ForEach(Array(manager.allItems.enumerated()), id: \.element.id) { index, fileInfo in
                                FileTreeRow(
                                    fileInfo: fileInfo,
                                    manager: manager,
                                    index: index,
                                    depth: childDepth,
                                    indentStep: indentStep
                                )
                                .id(fileInfo.id)
                            }
                        }

                    }

                    // Empty space area for folder right-click
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 200)
                        .contentShape(Rectangle())
                        .folderBackgroundContextMenu(url: manager.currentPath)
                }
                .id("\(manager.currentPath.absoluteString)_\(settings.flatFolders)")
                .onChange(of: manager.selectedIndex) { newIndex in
                    if newIndex >= 0, let item = manager.allItems[safe: newIndex] {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            proxy.scrollTo(item.id, anchor: .center)
                        }
                    }
                }
                .overlay(
                    Group {
                        if isDragOver {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.accentColor.opacity(0.08))
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.accentColor, lineWidth: 3)
                        }
                    }
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

        collectDropURLs(from: providers) { uniqueURLs in
            Task.detached {
                for srcURL in uniqueURLs {
                    if srcURL.deletingLastPathComponent().path == currentPath.path { continue }

                    let destURL = currentPath.appendingPathComponent(srcURL.lastPathComponent)
                    do {
                        var finalURL = destURL
                        var counter = 1
                        while FileManager.default.fileExists(atPath: finalURL.path) {
                            let baseName = destURL.deletingPathExtension().lastPathComponent
                            let ext = destURL.pathExtension
                            let newName = ext.isEmpty ? "\(baseName) \(counter)" : "\(baseName) \(counter).\(ext)"
                            finalURL = currentPath.appendingPathComponent(newName)
                            counter += 1
                        }

                        try FileManager.default.copyItem(at: srcURL, to: finalURL)
                        await MainActor.run {
                            ToastManager.shared.show("Copied \(srcURL.lastPathComponent)")
                        }
                    } catch {
                        await MainActor.run {
                            ToastManager.shared.show("Drop error: \(error.localizedDescription)")
                        }
                    }
                }

                await MainActor.run {
                    self.manager.refresh()
                }
            }
        }
    }
}

// Safe array subscript
extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

struct FlatBreadcrumbRow: View {
    let ancestors: [(name: String, url: URL)]
    @ObservedObject var manager: FileExplorerManager
    @ObservedObject var shortcutsManager = ShortcutsManager.shared
    @ObservedObject var folderIconManager = FolderIconManager.shared

    private var isPinned: Bool {
        shortcutsManager.customFolders.contains(where: { $0.path == manager.currentPath.path })
    }

    private var isSelected: Bool {
        manager.selectedItem == manager.currentPath
    }

    var body: some View {
        HStack(spacing: 4) {
            FolderIconView(url: manager.currentPath, size: 20)

            ForEach(Array(ancestors.enumerated()), id: \.element.url) { index, ancestor in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .textStyle(.small)
                        .foregroundColor(.secondary.opacity(0.5))
                }

                let isCurrent = ancestor.url.path == manager.currentPath.path
                Text(ancestor.name)
                    .textStyle(.default, weight: isCurrent ? .semibold : .regular)
                    .foregroundColor(isCurrent ? .primary : .secondary)
                    .lineLimit(1)
                    .onTapGesture {
                        if !isCurrent {
                            manager.navigateTo(ancestor.url)
                        } else if isSelected {
                            manager.selectedItem = nil
                            manager.selectedIndex = -1
                        } else {
                            manager.selectedItem = ancestor.url
                            manager.selectedIndex = -1
                        }
                    }
            }

            if manager.hiddenCount > 0 {
                Text("· \(manager.hiddenCount) hidden")
                    .textStyle(.buttons)
                    .foregroundColor(.secondary.opacity(0.6))
            }

            Button(action: {
                if isPinned {
                    shortcutsManager.removeFolder(manager.currentPath)
                } else {
                    shortcutsManager.addFolder(manager.currentPath)
                }
            }) {
                HStack(spacing: 2) {
                    Text("·")
                        .foregroundColor(.secondary.opacity(0.5))
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                        .foregroundColor(isPinned ? .orange : .secondary.opacity(0.5))
                        .offset(y: 2)
                }
                .textStyle(.small)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .selectedBackground(isSelected)
        .contentShape(Rectangle())
    }
}

struct AncestorRow: View {
    let name: String
    let url: URL
    let depth: Int
    let isCurrent: Bool
    let indentStep: CGFloat
    @ObservedObject var manager: FileExplorerManager
    @ObservedObject var shortcutsManager = ShortcutsManager.shared
    @ObservedObject var folderIconManager = FolderIconManager.shared

    private var isSelected: Bool {
        manager.selectedItem == url
    }

    private var isPinned: Bool {
        shortcutsManager.customFolders.contains(where: { $0.path == manager.currentPath.path })
    }

    var body: some View {
        HStack(spacing: 6) {
            FolderIconView(url: url, size: 20)

            Text(name)
                .textStyle(.default, weight: isCurrent ? .semibold : .regular)
                .foregroundColor(isCurrent ? .primary : .secondary)
                .lineLimit(1)

            if isCurrent && manager.hiddenCount > 0 {
                Text("· \(manager.hiddenCount) hidden")
                    .textStyle(.buttons)
                    .foregroundColor(.secondary.opacity(0.6))
            }

            if isCurrent {
                Button(action: {
                    if isPinned {
                        shortcutsManager.removeFolder(manager.currentPath)
                    } else {
                        shortcutsManager.addFolder(manager.currentPath)
                    }
                }) {
                    HStack(spacing: 2) {
                        Text("·")
                            .foregroundColor(.secondary.opacity(0.5))
                        Image(systemName: isPinned ? "pin.fill" : "pin")
                            .foregroundColor(isPinned ? .orange : .secondary.opacity(0.5))
                            .offset(y: 2)
                    }
                    .textStyle(.small)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
            }

            Spacer()
        }
        .padding(.leading, CGFloat(depth) * indentStep + 12)
        .padding(.trailing, 12)
        .padding(.vertical, 4)
        .selectedBackground(isSelected)
        .contentShape(Rectangle())
        .onTapGesture {
            if isCurrent {
                if isSelected {
                    manager.selectedItem = nil
                    manager.selectedIndex = -1
                } else {
                    manager.selectedItem = url
                    manager.selectedIndex = -1
                }
            } else {
                manager.navigateTo(url)
            }
        }
        .customContextMenu(url: url, isDirectory: true)
    }
}

struct FileTreeRow: View {
    let fileInfo: CachedFileInfo
    @ObservedObject var manager: FileExplorerManager
    @ObservedObject var selection = SelectionManager.shared
    @ObservedObject var tagManager = ColorTagManager.shared
    let index: Int
    let depth: Int
    let indentStep: CGFloat
    @State private var lastClickTime: Date = .distantPast
    @State private var isHovered = false

    private var url: URL { fileInfo.url }
    private var isDirectory: Bool { fileInfo.isDirectory }

    private var isSelected: Bool {
        manager.selectedIndex == index && manager.selectedItem == url
    }

    private var isCentralPaneFocused: Bool {
        !manager.sidebarFocused && !manager.rightPaneFocused
    }

    private var isInSelection: Bool {
        let _ = selection.version
        return selection.items.contains { $0.localURL == url }
    }

    private var isHidden: Bool { fileInfo.isHidden }

    private var isRenaming: Bool {
        manager.renamingItem == url
    }

    private var fileColors: [TagColor] {
        let _ = tagManager.version
        return tagManager.colorsForFile(url)
    }

    private var humanReadableDate: String {
        guard let date = fileInfo.modDate else { return "" }
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "just now" }
        else if interval < 3600 {
            let mins = Int(interval / 60)
            return "\(mins)m"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h"
        } else if interval < 86400 * 30 {
            let days = Int(interval / 86400)
            return "\(days)d"
        } else if interval < 86400 * 365 {
            let months = Int(interval / (86400 * 30))
            return "\(months)mo"
        } else {
            let years = Int(interval / (86400 * 365))
            return "\(years)y"
        }
    }

    private var fileSizeDisplay: String {
        if isDirectory { return "" }
        return compactTreeFileSize(fileInfo.size)
    }

    var body: some View {
        HStack(spacing: 6) {
            if isDirectory {
                FolderIconView(url: url, size: 22)
                    .overlay(alignment: .leading) {
                        Button(action: { manager.navigateTo(url) }) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.secondary.opacity(0.5))
                                .frame(width: 16, height: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .offset(x: -18)
                        .opacity(isHovered ? 1 : 0)
                        .onHover { inside in
                            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                        }
                    }
            } else {
                Image(nsImage: IconProvider.shared.icon(for: url, isDirectory: false))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 22, height: 22)
            }

            Text(url.lastPathComponent)
                .textStyle(.default)
                .lineLimit(1)
                .foregroundColor(.primary)

            if !fileColors.isEmpty {
                HStack(spacing: 2) {
                    ForEach(fileColors) { c in
                        Circle()
                            .fill(c.color)
                            .frame(width: 7, height: 7)
                    }
                }
            }

            Spacer()

            if manager.sortMode == .modified && !humanReadableDate.isEmpty {
                Text(humanReadableDate)
                    .textStyle(.buttons)
                    .foregroundColor(.secondary)
            }

            if !fileSizeDisplay.isEmpty {
                Text(fileSizeDisplay)
                    .textStyle(.buttons)
                    .foregroundColor(.secondary)
                    .frame(width: 60, alignment: .trailing)
            }
        }
        .padding(.leading, CGFloat(depth) * indentStep + 12)
        .padding(.trailing, 12)
        .padding(.vertical, 5)
        .rowHighlight(
            isSelected: isSelected,
            isFocused: isSelected && isCentralPaneFocused,
            isHovered: isHovered,
            isInSelection: isInSelection
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onDrag {
            return NSItemProvider(object: url as NSURL)
        }
        .onTapGesture {
            let now = Date()
            if now.timeIntervalSince(lastClickTime) < 0.3 {
                // Double click
                if isDirectory {
                    manager.navigateTo(url)
                } else {
                    manager.openItem(url)
                }
                lastClickTime = .distantPast
            } else {
                // Single click — select only, no navigate
                if manager.selectedItem == url {
                    manager.selectedItem = nil
                    manager.selectedIndex = -1
                } else {
                    manager.selectItem(at: index, url: url)
                }
                lastClickTime = now
            }
        }
        .opacity(isHidden ? 0.5 : 1.0)
        .customContextMenu(url: url, isDirectory: isDirectory)
    }
}

private func compactTreeFileSize(_ bytes: Int64) -> String {
    formatCompactSize(bytes)
}
