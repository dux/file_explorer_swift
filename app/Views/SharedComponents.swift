import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Drop Helpers

/// Collects file URLs from drop providers, deduplicates, then calls back on main with unique URLs.
func collectDropURLs(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
    let collector = URLCollector()
    let group = DispatchGroup()

    for provider in providers {
        group.enter()
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
            defer { group.leave() }
            guard let data = data as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            collector.add(url)
        }
    }

    group.notify(queue: .main) {
        completion(collector.uniqueURLs)
    }
}

private final class URLCollector: @unchecked Sendable {
    private var urls: [URL] = []
    private let lock = NSLock()

    func add(_ url: URL) {
        lock.lock()
        urls.append(url)
        lock.unlock()
    }

    var uniqueURLs: [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.path).inserted }
    }
}

// MARK: - Shared File Extension Sets

enum FileExtensions {
    static let images: Set<String> = ["jpg", "jpeg", "png", "gif", "bmp", "webp", "heic", "heif", "tiff", "tif", "svg", "avif"]
    static let audio: Set<String> = ["mp3", "m4a", "wav", "aac", "flac", "ogg", "wma", "aiff", "aif", "alac", "opus"]
    static let video: Set<String> = ["mp4", "mov", "m4v", "avi", "mkv", "webm", "wmv", "flv", "ogv", "3gp"]
    static let archives: Set<String> = ["zip", "tar", "tgz", "gz", "bz2", "xz", "rar", "7z"]
    static let office: Set<String> = ["docx", "xlsx", "pptx", "doc", "xls", "ppt"]
    static let comicImages: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "bmp", "avif"]

    static let previewable: Set<String> = {
        var s = images
        s.formUnion(["txt", "md", "json", "xml", "yaml", "yml"])
        s.formUnion(["py", "js", "ts", "swift", "rb", "go", "rs", "c", "cpp", "h"])
        s.formUnion(["html", "css", "sh", "log"])
        s.formUnion(["mp3", "m4a", "wav", "aac", "flac", "ogg", "aiff"])
        s.formUnion(["mp4", "mov", "m4v"])
        return s
    }()
}

// MARK: - Shared Formatters

func formatTime(_ time: Double) -> String {
    guard time.isFinite && time >= 0 else { return "0:00" }
    let hours = Int(time) / 3600
    let minutes = (Int(time) % 3600) / 60
    let seconds = Int(time) % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
    return String(format: "%d:%02d", minutes, seconds)
}

func formatCompactSize(_ bytes: Int64) -> String {
    if bytes < 1024 { return "\(bytes) b" }
    if bytes < 1024 * 1024 { return String(format: "%.1f kb", Double(bytes) / 1024) }
    if bytes < 1024 * 1024 * 1024 { return String(format: "%.1f mb", Double(bytes) / (1024 * 1024)) }
    return String(format: "%.1f gb", Double(bytes) / (1024 * 1024 * 1024))
}

func formatRelativeDate(_ date: Date?) -> String {
    guard let date else { return "--" }
    let interval = Date().timeIntervalSince(date)
    if interval < 60 { return "just now" }
    if interval < 3600 {
        let mins = Int(interval / 60)
        return "\(mins) minute\(mins == 1 ? "" : "s")"
    }
    if interval < 86400 {
        let hours = Int(interval / 3600)
        let mins = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)
        if mins > 0 { return "\(hours) hour\(hours == 1 ? "" : "s") & \(mins) min" }
        return "\(hours) hour\(hours == 1 ? "" : "s")"
    }
    if interval < 86400 * 30 {
        let days = Int(interval / 86400)
        let hours = Int((interval.truncatingRemainder(dividingBy: 86400)) / 3600)
        if hours > 0 && days < 7 { return "\(days) day\(days == 1 ? "" : "s") & \(hours) hour\(hours == 1 ? "" : "s")" }
        return "\(days) day\(days == 1 ? "" : "s")"
    }
    if interval < 86400 * 365 {
        let months = Int(interval / (86400 * 30))
        let days = Int((interval.truncatingRemainder(dividingBy: 86400 * 30)) / 86400)
        if days > 0 && months < 6 { return "\(months) month\(months == 1 ? "" : "s") & \(days) day\(days == 1 ? "" : "s")" }
        return "\(months) month\(months == 1 ? "" : "s")"
    }
    let years = Int(interval / (86400 * 365))
    let months = Int((interval.truncatingRemainder(dividingBy: 86400 * 365)) / (86400 * 30))
    if months > 0 { return "\(years) year\(years == 1 ? "" : "s") & \(months) month\(months == 1 ? "" : "s")" }
    return "\(years) year\(years == 1 ? "" : "s")"
}

// MARK: - Shared Utility Functions

private let sharedDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter
}()

func formatDateShort(_ date: Date) -> String {
    sharedDateFormatter.string(from: date)
}

func calculateFileSize(url: URL, isDirectory: Bool, completion: @MainActor @escaping (String, Int?) -> Void) {
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
                completion(sizeStr, count)
            }
        } else {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? UInt64 {
                let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
                DispatchQueue.main.async {
                    completion(sizeStr, nil)
                }
            }
        }
    }
}

// MARK: - Sheet Header

struct SheetHeader: View {
    let icon: String
    let title: String
    var color: Color = .accentColor
    @Binding var isPresented: Bool

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(color)
            Text(title)
                .textStyle(.default, weight: .semibold)
            Spacer()
            SheetCloseButton(isPresented: $isPresented)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - Sheet Close Button

struct SheetCloseButton: View {
    @Binding var isPresented: Bool

    var body: some View {
        Button(action: { isPresented = false }) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 18))
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sheet Footer (filename + close)

struct SheetFooter: View {
    let filename: String
    @Binding var isPresented: Bool

    var body: some View {
        HStack {
            Text(filename)
                .textStyle(.buttons)
                .foregroundColor(.secondary)
                .lineLimit(1)
            Spacer()
            Button("Close") {
                isPresented = false
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - Loading State View

struct LoadingStateView: View {
    var message: String = "Loading..."

    var body: some View {
        VStack {
            ProgressView()
            Text(message)
                .textStyle(.default)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Error State View

struct ErrorStateView: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundColor(.orange)
            Text(message)
                .textStyle(.default)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Empty State View

struct EmptyStateView: View {
    var icon: String = "tray"
    var message: String = "Nothing here"

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text(message)
                .textStyle(.default)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Metadata Table View

struct MetadataTableView: View {
    let items: [(key: String, value: String)]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(items, id: \.key) { item in
                    HStack(alignment: .top) {
                        Text(item.key)
                            .textStyle(.buttons)
                            .foregroundColor(.secondary)
                            .frame(width: 140, alignment: .trailing)
                        Text(item.value)
                            .textStyle(.buttons)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    Divider()
                        .padding(.leading, 160)
                }
            }
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Font Size Controls

struct FontSizeControls: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        HStack(spacing: 4) {
            Button(action: { settings.decreaseFontSize() }) {
                Image(systemName: "minus")
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.borderless)
            Text("\(Int(settings.previewFontSize))px")
                .textStyle(.small)
                .foregroundColor(.secondary)
                .frame(width: 32)
            Button(action: { settings.increaseFontSize() }) {
                Image(systemName: "plus")
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.borderless)
        }
        .padding(.trailing, 8)
    }
}

// MARK: - File Context Menu Items

struct FileContextMenuItems: View {
    let url: URL
    let isDirectory: Bool
    let manager: FileExplorerManager
    let tagManager: ColorTagManager
    @Binding var showingDetails: Bool

    var body: some View {
        Button(action: { showingDetails = true }) {
            Label("View Details", systemImage: "info.circle")
        }
        Button(action: { manager.toggleFileSelection(url) }) {
            Label(manager.isInSelection(url) ? "Remove from Selection" : "Add to Selection",
                  systemImage: manager.isInSelection(url) ? "minus.circle" : "checkmark.circle")
        }
        Button(action: {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(url.path, forType: .string)
            ToastManager.shared.show("Path copied to clipboard")
        }) {
            Label("Copy Path", systemImage: "doc.on.clipboard")
        }
        Button(action: {
            manager.selectedItem = url
            manager.startRename()
        }) {
            Label("Rename", systemImage: "pencil")
        }
        Button(action: {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }) {
            Label("Show in Finder", systemImage: "folder")
        }
        Divider()
        Button(action: { manager.duplicateFile(url) }) {
            Label("Duplicate", systemImage: "doc.on.doc")
        }
        Button(action: { manager.addToZip(url) }) {
            Label("Add to Zip", systemImage: "doc.zipper")
        }
        if ["zip", "tar", "tgz", "gz", "bz2", "xz", "rar", "7z"].contains(url.pathExtension.lowercased()) {
            Button(action: { manager.extractArchive(url) }) {
                Label("Extract to folder", systemImage: "arrow.down.doc")
            }
        }
        if url.pathExtension.lowercased() == "app" && isDirectory {
            Button(action: { manager.enableUnsafeApp(url) }) {
                Label("Enable unsafe app", systemImage: "checkmark.shield")
            }
        }
        if url.lastPathComponent.hasPrefix(".") {
            Button(action: { manager.toggleHidden(url) }) {
                Label("Make Visible", systemImage: "eye")
            }
        } else {
            Button(action: { manager.toggleHidden(url) }) {
                Label("Make Hidden", systemImage: "eye.slash")
            }
        }
        Divider()
        Button(role: .destructive, action: { manager.moveToTrash(url) }) {
            Label("Move to Trash", systemImage: "trash")
        }
        Divider()
        ColorTagMenuItems(url: url, tagManager: tagManager)
    }
}

// MARK: - Drop-on-App Handler

func handleFileDrop(providers: [NSItemProvider], appURL: URL) -> Bool {
    for provider in providers {
        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
            guard let data = item as? Data,
                  let fileURL = URL(dataRepresentation: data, relativeTo: nil) else { return }
            DispatchQueue.main.async {
                NSWorkspace.shared.open([fileURL], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
            }
        }
    }
    return true
}
