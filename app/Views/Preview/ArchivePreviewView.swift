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
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.system(size: 13))
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
                .font(.system(size: 12, weight: .medium))
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
                                manager: manager
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
                .font(.system(size: 12))
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

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")

        switch ext {
        case "zip":
            process.arguments = ["unzip", "-l", url.path]
        case "tar", "tgz", "gz", "bz2", "xz":
            process.arguments = ["tar", "-tvf", url.path]
        case "rar":
            process.arguments = ["unrar", "l", url.path]
        case "7z":
            process.arguments = ["7z", "l", url.path]
        default:
            process.arguments = ["unzip", "-l", url.path]
        }

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

            let entries = parseArchiveOutput(output: output, type: ext).sorted { a, b in
                if a.isDirectory != b.isDirectory { return a.isDirectory }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
            return .success(entries)
        } catch {
            return .failure(error)
        }
    }

    nonisolated private static func parseArchiveOutput(output: String, type: String) -> [ArchiveEntry] {
        var entries: [ArchiveEntry] = []
        let lines = output.components(separatedBy: .newlines)

        switch type {
        case "zip":
            var inFileList = false
            for line in lines {
                if line.contains("--------") {
                    inFileList.toggle()
                    continue
                }
                if inFileList && !line.isEmpty {
                    let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
                    if parts.count >= 4 {
                        let size = UInt64(parts[0]) ?? 0
                        let path = String(parts[3])
                        let name = URL(fileURLWithPath: path).lastPathComponent
                        let isDir = path.hasSuffix("/")
                        entries.append(ArchiveEntry(path: path, name: name, size: size, isDirectory: isDir, compressedSize: nil))
                    }
                }
            }

        case "tar", "tgz", "gz", "bz2", "xz":
            for line in lines {
                let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                if parts.count >= 6 {
                    let perms = String(parts[0])
                    let isDir = perms.hasPrefix("d")
                    let size = UInt64(parts[2]) ?? 0
                    let path = parts.dropFirst(5).joined(separator: " ")
                    let name = URL(fileURLWithPath: path).lastPathComponent
                    if !name.isEmpty {
                        entries.append(ArchiveEntry(path: path, name: name, size: size, isDirectory: isDir, compressedSize: nil))
                    }
                }
            }

        default:
            for line in lines where !line.isEmpty {
                entries.append(ArchiveEntry(path: line, name: line, size: 0, isDirectory: false, compressedSize: nil))
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

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: entryIcon)
                .resizable()
                .frame(width: 22, height: 22)

            Text(entry.name)
                .font(.system(size: 14))
                .lineLimit(1)
                .foregroundColor(isSelected ? .white : .primary)

            Spacer()

            Text(entry.isDirectory ? "" : entry.displaySize)
                .font(.system(size: 11))
                .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary)
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.trailing, 12)
        .padding(.vertical, 5)
        .background(isSelected ? Color.accentColor : Color.clear)
        .cornerRadius(4)
        .contentShape(Rectangle())
        .onDrag {
            let tempURL = extractToTemp()
            if let url = tempURL {
                return NSItemProvider(object: url as NSURL)
            }
            return NSItemProvider()
        }
    }

    private func extractToTemp() -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArchiveExtract")
            .appendingPathComponent(UUID().uuidString)

        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let ext = archiveURL.pathExtension.lowercased()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.currentDirectoryURL = tempDir

        switch ext {
        case "zip":
            process.arguments = ["unzip", "-o", archiveURL.path, entry.path, "-d", tempDir.path]
        case "tar", "tgz", "gz", "bz2", "xz":
            process.arguments = ["tar", "-xf", archiveURL.path, "-C", tempDir.path, entry.path]
        default:
            return nil
        }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            _ = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            let extractedURL = tempDir.appendingPathComponent(entry.path)
            if FileManager.default.fileExists(atPath: extractedURL.path) {
                return extractedURL
            }
        } catch {
            ToastManager.shared.showError("Extract error: \(error.localizedDescription)")
        }

        return nil
    }
}
