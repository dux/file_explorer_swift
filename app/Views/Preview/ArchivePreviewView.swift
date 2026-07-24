import SwiftUI
import UniformTypeIdentifiers

struct ArchiveEntry: Identifiable, Hashable {
    let id = UUID()
    let path: String
    let name: String
    let size: UInt64
    let isDirectory: Bool
    let compressedSize: UInt64?

    var displaySize: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}

struct ArchivePreviewView: View {
    let url: URL
    @ObservedObject var manager: FileExplorerManager
    @State private var entries: [ArchiveEntry] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedEntry: ArchiveEntry?
    @State private var isDragOver = false

    var body: some View {
        VStack(spacing: 0) {
            PreviewHeader(title: "Archive preview", icon: "doc.zipper", color: .brown)
            Divider()

            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Reading archive...")
                        .textStyle(.buttons)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundColor(.orange)
                    Text(error)
                        .textStyle(.buttons)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    Text("Name")
                        .frame(minWidth: 200, alignment: .leading)
                    Spacer()
                    Text("Size")
                        .frame(width: 80, alignment: .trailing)
                }
                .textStyle(.small, weight: .medium)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

                Divider()

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(entries) { entry in
                            ArchiveEntryRow(
                                entry: entry,
                                isSelected: selectedEntry?.id == entry.id,
                                archiveURL: url,
                                manager: manager,
                                onReload: { loadArchive() }
                            )
                            .onTapGesture {
                                selectedEntry = entry
                            }
                        }
                    }
                }

                Divider()

                HStack {
                    Text("\(entries.count) items")
                    Spacer()
                    Text(totalSize)
                }
                .textStyle(.small)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isDragOver ? Color.accentColor : Color.clear, lineWidth: 3)
                .background(isDragOver ? Color.accentColor.opacity(0.08) : Color.clear)
                .cornerRadius(8)
                .allowsHitTesting(false)
        )
        .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
            handleDrop(providers: providers)
            return true
        }
        .onAppear { loadArchive() }
        .onChange(of: url) { _ in loadArchive() }
    }

    private var totalSize: String {
        let total = entries.reduce(0) { $0 + $1.size }
        return ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file)
    }

    private func loadArchive() {
        isLoading = true
        errorMessage = nil
        entries = []

        let archiveURL = url
        Task.detached {
            let result = Self.listArchiveContents(url: archiveURL)
            await MainActor.run {
                isLoading = false
                switch result {
                case .success(let items):
                    entries = items
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    nonisolated private static func listArchiveContents(url: URL) -> Result<[ArchiveEntry], Error> {
        let ext = url.pathExtension.lowercased()
        let name = url.lastPathComponent.lowercased()
        let isTarball = [".tar.gz", ".tar.bz2", ".tar.xz", ".tar.zst"].contains { name.hasSuffix($0) }

        // Bare compressed file: exactly one inner file, nothing to list
        if !isTarball, ["gz", "bz2", "xz", "zst"].contains(ext) {
            let inner = url.deletingPathExtension().lastPathComponent
            return .success([ArchiveEntry(path: inner, name: inner, size: 0, isDirectory: false, compressedSize: nil)])
        }

        // bsdtar/libarchive lists every container format (zip, tar*, 7z, rar)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-tvf", url.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            // Read pipe BEFORE waitUntilExit to prevent deadlock
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard let output = String(data: data, encoding: .utf8) else {
                return .failure(NSError(domain: "Archive", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not read archive"]))
            }

            let entries = parseArchiveOutput(output: output).sorted { a, b in
                if a.isDirectory != b.isDirectory { return a.isDirectory }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
            return .success(entries)
        } catch {
            return .failure(error)
        }
    }

    // bsdtar -tvf prints ls -l style rows:
    //   -rw-r--r--  0 501  20  1234 Jul 24 08:13 dir/file.txt
    // size is column 4, the path starts at column 8 (month day time/year in between).
    nonisolated private static func parseArchiveOutput(output: String) -> [ArchiveEntry] {
        var entries: [ArchiveEntry] = []

        for line in output.components(separatedBy: .newlines) {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 9 else { continue }
            let perms = String(parts[0])
            let size = UInt64(parts[4]) ?? 0
            var path = parts.dropFirst(8).joined(separator: " ")
            if perms.hasPrefix("l"), let range = path.range(of: " -> ") {
                path = String(path[..<range.lowerBound])
            }
            let isDir = perms.hasPrefix("d") || path.hasSuffix("/")
            let name = URL(fileURLWithPath: path).lastPathComponent
            if !name.isEmpty {
                entries.append(ArchiveEntry(path: path, name: name, size: size, isDirectory: isDir, compressedSize: nil))
            }
        }

        return entries
    }

    private func handleDrop(providers: [NSItemProvider]) {
        let archiveURL = url
        let ext = archiveURL.pathExtension.lowercased()
        guard ext == "zip" || ext == "tar" else {
            ToastManager.shared.show("Can only add to .zip and .tar")
            return
        }

        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, error in
                guard let data = data as? Data,
                      let fileURL = URL(dataRepresentation: data, relativeTo: nil) else { return }

                let fileName = fileURL.lastPathComponent
                Task.detached {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                    process.currentDirectoryURL = fileURL.deletingLastPathComponent()

                    switch ext {
                    case "zip":
                        process.arguments = ["zip", "-r", archiveURL.path, fileName]
                    case "tar":
                        process.arguments = ["tar", "-rf", archiveURL.path, fileName]
                    default:
                        return
                    }

                    let pipe = Pipe()
                    process.standardOutput = pipe
                    process.standardError = pipe

                    do {
                        try process.run()
                        _ = pipe.fileHandleForReading.readDataToEndOfFile()
                        process.waitUntilExit()

                        await MainActor.run {
                            ToastManager.shared.show("Added \(fileName) to archive")
                            loadArchive()
                        }
                    } catch {
                        await MainActor.run {
                            ToastManager.shared.show("Error: \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
    }
}

struct ArchiveEntryRow: View {
    let entry: ArchiveEntry
    let isSelected: Bool
    let archiveURL: URL
    @ObservedObject var manager: FileExplorerManager
    var onReload: () -> Void = {}

    private var entryIcon: NSImage {
        if entry.isDirectory {
            return NSWorkspace.shared.icon(for: .folder)
        }
        let ext = URL(fileURLWithPath: entry.path).pathExtension.lowercased()
        if let utType = UTType(filenameExtension: ext) {
            return NSWorkspace.shared.icon(for: utType)
        }
        return NSWorkspace.shared.icon(for: .item)
    }

    private var archiveExt: String {
        archiveURL.pathExtension.lowercased()
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: entryIcon)
                .resizable()
                .frame(width: 22, height: 22)

            Text(entryDisplayName)
                .textStyle(.default)
                .lineLimit(1)
                .foregroundColor(.primary)

            Spacer()

            Text(entry.isDirectory ? "" : entry.displaySize)
                .textStyle(.small)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.trailing, 12)
        .padding(.vertical, 5)
        .selectedBackground(isSelected)
        .cornerRadius(4)
        .contentShape(Rectangle())
        .contextMenu {
            Button(action: { extractToCurrent() }) {
                Label("Extract to folder", systemImage: "arrow.down.doc")
            }
            if archiveExt == "zip" {
                Divider()
                Button(role: .destructive, action: { deleteFromArchive() }) {
                    Label("Delete from archive", systemImage: "trash")
                }
            }
        }
        .onDrag {
            let pending = ArchiveDragSession.Pending(
                archive: archiveURL,
                entryPath: entry.path,
                entryName: entry.name,
                isDirectory: entry.isDirectory,
                archiveExt: archiveExt
            )
            let draggedURL = ArchiveDragSession.shared.beginDrag(pending: pending) {
                manager.refresh()
            }
            return NSItemProvider(object: draggedURL as NSURL)
        }
    }

    private var entryDisplayName: String {
        entry.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func extractToCurrent() {
        let destDir = manager.currentPath
        let arc = archiveURL
        let ent = entry
        let ext = archiveExt
        ToastManager.shared.show("Extracting \(ent.name)...")
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            switch ext {
            case "zip":
                process.arguments = ["unzip", "-o", arc.path, ent.path, "-d", destDir.path]
            case "tar", "tgz", "gz", "bz2", "xz":
                process.arguments = ["tar", "-xf", arc.path, "-C", destDir.path, ent.path]
            default:
                await MainActor.run { ToastManager.shared.showError("Unsupported format") }
                return
            }
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
                _ = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let success = process.terminationStatus == 0
                await MainActor.run {
                    if success {
                        ToastManager.shared.show("Extracted \(ent.name)")
                        manager.refresh()
                    } else {
                        ToastManager.shared.showError("Failed to extract \(ent.name)")
                    }
                }
            } catch {
                await MainActor.run {
                    ToastManager.shared.showError("Extract error: \(error.localizedDescription)")
                }
            }
        }
    }

    private func deleteFromArchive() {
        let arc = archiveURL
        let ent = entry
        ToastManager.shared.show("Deleting \(ent.name)...")
        Task.detached {
            let process = Process()
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            if ent.isDirectory {
                // Shell glob needed for directory contents
                let escaped = arc.path.replacingOccurrences(of: "'", with: "'\\''")
                let entEscaped = ent.path.replacingOccurrences(of: "'", with: "'\\''")
                process.executableURL = URL(fileURLWithPath: "/bin/sh")
                process.arguments = ["-c", "zip -d '\(escaped)' '\(entEscaped)' '\(entEscaped)*'"]
            } else {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
                process.arguments = ["-d", arc.path, ent.path]
            }
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let status = process.terminationStatus
                await MainActor.run {
                    if status == 0 {
                        ToastManager.shared.show("Deleted \(ent.name) from archive")
                        onReload()
                    } else {
                        let msg = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown error"
                        ToastManager.shared.showError("Delete failed: \(msg)")
                    }
                }
            } catch {
                await MainActor.run {
                    ToastManager.shared.showError("Delete error: \(error.localizedDescription)")
                }
            }
        }
    }

}
