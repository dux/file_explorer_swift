import SwiftUI
import UniformTypeIdentifiers

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
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(manager.allItems.enumerated()), id: \.element.id) { index, fileInfo in
                            FileTableRow(fileInfo: fileInfo, manager: manager, index: index)
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

struct FileTableRow: View {
    let fileInfo: CachedFileInfo
    @ObservedObject var manager: FileExplorerManager
    @ObservedObject var selection = SelectionManager.shared
    @ObservedObject var tagManager = ColorTagManager.shared
    let index: Int
    @State private var showingDetails = false
    @State private var lastClickTime: Date = .distantPast


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

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 10) {
                if isDirectory {
                    FolderIconView(url: url, size: 24, selected: isSelected)
                } else {
                    Image(nsImage: IconProvider.shared.icon(for: url, isDirectory: false, selected: isSelected))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 24, height: 24)
                }

                Text(url.lastPathComponent)
                    .font(.system(size: 14))
                    .lineLimit(1)
                    .foregroundColor(isSelected ? .white : .primary)

                if !fileColors.isEmpty {
                    HStack(spacing: 2) {
                        ForEach(fileColors) { c in
                            Circle()
                                .fill(c.color)
                                .frame(width: 7, height: 7)
                        }
                    }
                }
            }
            .frame(minWidth: 250, alignment: .leading)

            Spacer()

            if manager.sortMode == .modified {
                Text(humanReadableDate)
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                    .frame(width: 180, alignment: .leading)
            }

            Text(fileSizeDisplay)
                .font(.system(size: 14))
                .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            isSelected ? Color.accentColor :
            (isInSelection ? Color.green.opacity(0.15) : Color.clear)
        )
        .contentShape(Rectangle())
        .onDrag {
            return NSItemProvider(object: url as NSURL)
        }
        .onTapGesture {
            let now = Date()
            if now.timeIntervalSince(lastClickTime) < 0.3 {
                if isDirectory {
                    manager.navigateTo(url)
                } else {
                    manager.toggleFileSelection(url)
                }
                lastClickTime = .distantPast
            } else {
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
                Label("View Details", systemImage: "info.circle").font(.system(size: 15))
            }
            Button(action: { manager.toggleFileSelection(url) }) {
                Label(manager.isInSelection(url) ? "Remove from Selection" : "Add to Selection",
                      systemImage: manager.isInSelection(url) ? "minus.circle" : "checkmark.circle").font(.system(size: 15))
            }
            Button(action: {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(url.path, forType: .string)
            }) {
                Label("Copy Path", systemImage: "doc.on.clipboard").font(.system(size: 15))
            }
            Button(action: {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }) {
                Label("Show in Finder", systemImage: "folder").font(.system(size: 15))
            }
            Divider()
            Button(action: { manager.duplicateFile(url) }) {
                Label("Duplicate", systemImage: "doc.on.doc").font(.system(size: 15))
            }
            Button(action: { manager.addToZip(url) }) {
                Label("Add to Zip", systemImage: "doc.zipper").font(.system(size: 15))
            }
            Divider()
            Button(role: .destructive, action: { manager.moveToTrash(url) }) {
                Label("Move to Trash", systemImage: "trash").font(.system(size: 15))
            }
            Divider()
            ColorTagMenuItems(url: url, tagManager: tagManager)
        }
        .sheet(isPresented: $showingDetails) {
            FileDetailsView(url: url, isDirectory: isDirectory)
        }
    }

    private var humanReadableDate: String {
        guard let date = fileInfo.modDate else { return "" }
        let now = Date()
        let interval = now.timeIntervalSince(date)
        if interval < 60 { return "just now" }
        else if interval < 3600 {
            let mins = Int(interval / 60)
            return "\(mins) minute\(mins == 1 ? "" : "s")"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            let mins = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)
            if mins > 0 { return "\(hours) hour\(hours == 1 ? "" : "s") & \(mins) min" }
            return "\(hours) hour\(hours == 1 ? "" : "s")"
        } else if interval < 86400 * 30 {
            let days = Int(interval / 86400)
            let hours = Int((interval.truncatingRemainder(dividingBy: 86400)) / 3600)
            if hours > 0 && days < 7 { return "\(days) day\(days == 1 ? "" : "s") & \(hours) hour\(hours == 1 ? "" : "s")" }
            return "\(days) day\(days == 1 ? "" : "s")"
        } else if interval < 86400 * 365 {
            let months = Int(interval / (86400 * 30))
            let days = Int((interval.truncatingRemainder(dividingBy: 86400 * 30)) / 86400)
            if days > 0 && months < 6 { return "\(months) month\(months == 1 ? "" : "s") & \(days) day\(days == 1 ? "" : "s")" }
            return "\(months) month\(months == 1 ? "" : "s")"
        } else {
            let years = Int(interval / (86400 * 365))
            let months = Int((interval.truncatingRemainder(dividingBy: 86400 * 365)) / (86400 * 30))
            if months > 0 { return "\(years) year\(years == 1 ? "" : "s") & \(months) month\(months == 1 ? "" : "s")" }
            return "\(years) year\(years == 1 ? "" : "s")"
        }
    }

    private var fileSizeDisplay: String {
        if isDirectory { return "--" }
        return compactFileSize(fileInfo.size)
    }
}

private func compactFileSize(_ bytes: Int64) -> String {
    if bytes < 1024 { return "\(bytes) b" }
    if bytes < 1024 * 1024 { return String(format: "%.1f kb", Double(bytes) / 1024) }
    if bytes < 1024 * 1024 * 1024 { return String(format: "%.1f mb", Double(bytes) / (1024 * 1024)) }
    return String(format: "%.1f gb", Double(bytes) / (1024 * 1024 * 1024))
}
