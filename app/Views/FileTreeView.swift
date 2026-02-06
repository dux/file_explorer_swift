import SwiftUI
import UniformTypeIdentifiers

// MARK: - File Tree View (ancestor path + children)

struct FileTreeView: View {
    @ObservedObject var manager: FileExplorerManager
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
            EmptyFolderView()
                .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
                    handleDrop(providers: providers)
                    return true
                }
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        Spacer().frame(height: 2)
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
                            let actualIndex = manager.allItems.firstIndex(where: { $0.url == fileInfo.url }) ?? -1
                            FileTreeRow(
                                fileInfo: fileInfo,
                                manager: manager,
                                index: actualIndex,
                                depth: childDepth,
                                indentStep: indentStep
                            )
                            .id(fileInfo.id)
                        }
                    }
                }
                .id(manager.currentPath.absoluteString)
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

struct AncestorRow: View {
    let name: String
    let url: URL
    let depth: Int
    let isCurrent: Bool
    let indentStep: CGFloat
    @ObservedObject var manager: FileExplorerManager
    @ObservedObject var shortcutsManager = ShortcutsManager.shared

    private var isSelected: Bool {
        manager.selectedItem == url
    }

    private var isPinned: Bool {
        shortcutsManager.customFolders.contains(where: { $0.path == manager.currentPath.path })
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: IconProvider.shared.icon(for: url, isDirectory: true, selected: isSelected))
                .resizable()
                .interpolation(.high)
                .frame(width: 20, height: 20)

            Text(name)
                .font(.system(size: 14, weight: isCurrent ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : (isCurrent ? .primary : .secondary))
                .lineLimit(1)

            if isCurrent && manager.hiddenCount > 0 {
                Text("+\(manager.hiddenCount) hidden")
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary.opacity(0.6))
            }

            Spacer()

            if isCurrent {
                Button(action: {
                    if isPinned {
                        shortcutsManager.removeFolder(manager.currentPath)
                    } else {
                        shortcutsManager.addFolder(manager.currentPath)
                    }
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: isPinned ? "pin.fill" : "pin")
                            .font(.system(size: 10))
                        Text(isPinned ? "unpin" : "pin folder")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(isPinned ? .orange : .secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, CGFloat(depth) * indentStep + 12)
        .padding(.trailing, 12)
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor : Color.clear)
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
    @State private var showingDetails = false
    @State private var lastClickTime: Date = .distantPast
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
        return ByteCountFormatter.string(fromByteCount: fileInfo.size, countStyle: .file)
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: IconProvider.shared.icon(for: url, isDirectory: isDirectory, selected: isSelected))
                .resizable()
                .interpolation(.high)
                .frame(width: 22, height: 22)

            if isRenaming {
                RenameTextField(text: $manager.renameText, onCommit: {
                    manager.confirmRename()
                }, onCancel: {
                    manager.cancelRename()
                })
                .frame(height: 20)
            } else {
                Text(url.lastPathComponent)
                    .font(.system(size: 14))
                    .lineLimit(1)
                    .foregroundColor(isSelected ? .white : .primary)
            }

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

            if !humanReadableDate.isEmpty {
                Text(humanReadableDate)
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary)
            }

            if !fileSizeDisplay.isEmpty {
                Text(fileSizeDisplay)
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary)
                    .frame(width: 60, alignment: .trailing)
            }
        }
        .padding(.leading, CGFloat(depth) * indentStep + 12)
        .padding(.trailing, 12)
        .padding(.vertical, 5)
        .background(
            isSelected ? Color.accentColor :
            (isInSelection ? Color.green.opacity(0.15) : Color.clear)
        )
        .contentShape(Rectangle())
        .onDrag {
            manager.selectedItem = nil
            manager.selectedIndex = -1
            return NSItemProvider(object: url as NSURL)
        }
        .onTapGesture {
            let now = Date()
            if now.timeIntervalSince(lastClickTime) < 0.3 {
                // Double click
                if isDirectory {
                    manager.navigateTo(url)
                } else {
                    manager.toggleFileSelection(url)
                }
                lastClickTime = .distantPast
            } else {
                // Single click
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
        .contextMenu {
            Button(action: { showingDetails = true }) {
                Label("View Details", systemImage: "info.circle")
            }
            Button(action: { manager.toggleFileSelection(url) }) {
                Label(manager.isInSelection(url) ? "Remove from Selection" : "Add to Selection",
                      systemImage: manager.isInSelection(url) ? "minus.circle" : "checkmark.circle")
            }
            Divider()
            ColorTagMenu(url: url, tagManager: tagManager)
            Divider()
            Button(action: { manager.duplicateFile(url) }) {
                Label("Duplicate", systemImage: "doc.on.doc")
            }
            Button(action: { manager.addToZip(url) }) {
                Label("Add to Zip", systemImage: "doc.zipper")
            }
            Divider()
            Button(role: .destructive, action: { manager.moveToTrash(url) }) {
                Label("Move to Trash", systemImage: "trash")
            }
        }
        .sheet(isPresented: $showingDetails) {
            FileDetailsView(url: url, isDirectory: isDirectory)
        }
    }
}
