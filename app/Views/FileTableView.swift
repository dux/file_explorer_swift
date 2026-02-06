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

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 24, height: 24)

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
            (isInSelection ? Color.green.opacity(0.15) : Color.clear)
        )
        .contentShape(Rectangle())
        .onAppear { }
        .onTapGesture {
            let now = Date()
            if now.timeIntervalSince(lastClickTime) < 0.3 {
                if isDirectory {
                    manager.navigateTo(url)
                } else {
                    manager.addFileToSelection(url)
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
        .onDrag {
            NSItemProvider(object: url as NSURL)
        }
        .opacity(isHidden ? 0.5 : 1.0)
        .contextMenu {
            Button(action: { showingDetails = true }) {
                Label("View Details", systemImage: "info.circle")
            }
            Button(action: { manager.addFileToSelection(url) }) {
                Label("Add to Selection", systemImage: "checkmark.circle")
            }
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

    private var iconForItem: String {
        if isDirectory { return "folder.fill" }
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "gif", "bmp", "webp", "heic", "tiff", "svg", "ico", "raw", "avif": return "photo.fill"
        case "pdf": return "doc.text.fill"
        case "txt", "rtf": return "doc.plaintext.fill"
        case "md", "markdown": return "text.document.fill"
        case "doc", "docx", "odt", "pages": return "doc.richtext.fill"
        case "xls", "xlsx", "csv", "numbers", "ods": return "tablecells.fill"
        case "ppt", "pptx", "key", "odp": return "slider.horizontal.below.rectangle"
        case "zip", "tar", "gz", "rar", "7z", "bz2", "xz", "dmg", "iso": return "doc.zipper"
        case "mp3", "wav", "m4a", "aac", "flac", "ogg", "wma", "aiff": return "waveform"
        case "mp4", "mov", "avi", "mkv", "webm", "wmv", "flv", "m4v": return "film.fill"
        case "swift": return "swift"
        case "py", "js", "ts", "jsx", "tsx", "c", "cpp", "h", "hpp", "m", "mm",
             "java", "kt", "scala", "rb", "php", "pl", "go", "rs", "zig": return "chevron.left.forwardslash.chevron.right"
        case "sh", "bash", "zsh", "fish": return "terminal.fill"
        case "html", "htm": return "globe"
        case "css", "scss", "sass", "less": return "paintbrush.fill"
        case "json", "xml", "yaml", "yml", "toml", "ini", "conf", "config": return "gearshape.fill"
        case "sql", "db", "sqlite": return "cylinder.fill"
        case "ttf", "otf", "woff", "woff2": return "textformat"
        case "app", "exe", "bin": return "app.fill"
        case "pkg", "deb", "rpm": return "shippingbox.fill"
        case "psd", "ai", "sketch", "fig", "xd": return "paintpalette.fill"
        case "obj", "fbx", "blend", "3ds", "dae": return "cube.fill"
        default: return "doc.fill"
        }
    }

    private var iconColor: Color {
        if isDirectory { return Color(red: 0.35, green: 0.67, blue: 0.95) }
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "gif", "bmp", "webp", "heic", "tiff", "svg", "ico", "raw", "avif": return Color(red: 0.69, green: 0.42, blue: 0.87)
        case "pdf": return Color(red: 0.92, green: 0.26, blue: 0.24)
        case "doc", "docx", "odt", "pages", "txt", "rtf", "md", "markdown": return Color(red: 0.26, green: 0.52, blue: 0.96)
        case "xls", "xlsx", "csv", "numbers", "ods": return Color(red: 0.21, green: 0.71, blue: 0.35)
        case "ppt", "pptx", "key", "odp": return Color(red: 0.96, green: 0.58, blue: 0.12)
        case "zip", "tar", "gz", "rar", "7z", "bz2", "xz", "dmg", "iso": return Color(red: 0.6, green: 0.5, blue: 0.4)
        case "mp3", "wav", "m4a", "aac", "flac", "ogg", "wma", "aiff": return Color(red: 0.95, green: 0.35, blue: 0.55)
        case "mp4", "mov", "avi", "mkv", "webm", "wmv", "flv", "m4v": return Color(red: 0.96, green: 0.42, blue: 0.32)
        case "swift", "py", "js", "ts", "jsx", "tsx", "c", "cpp", "h", "hpp", "m", "mm",
             "java", "kt", "scala", "rb", "php", "pl", "go", "rs", "zig", "sh", "bash", "zsh", "fish": return Color(red: 0.2, green: 0.75, blue: 0.75)
        case "html", "htm": return Color(red: 0.9, green: 0.45, blue: 0.2)
        case "css", "scss", "sass", "less": return Color(red: 0.26, green: 0.52, blue: 0.96)
        case "json", "xml", "yaml", "yml", "toml", "ini", "conf", "config": return Color(red: 0.55, green: 0.55, blue: 0.58)
        case "sql", "db", "sqlite": return Color(red: 0.55, green: 0.35, blue: 0.75)
        case "psd", "ai", "sketch", "fig", "xd": return Color(red: 0.85, green: 0.25, blue: 0.55)
        default: return .secondary
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
        return ByteCountFormatter.string(fromByteCount: fileInfo.size, countStyle: .file)
    }
}
