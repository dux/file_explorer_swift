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
    @State private var entries: [ArchiveEntry] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedEntry: ArchiveEntry?
    @State private var isDragOver = false

    var body: some View {
        VStack(spacing: 0) {
            PreviewHeader(title: url.lastPathComponent, icon: "doc.zipper", color: .brown)
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
                // Header
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

                // File list
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(entries) { entry in
                            ArchiveEntryRow(
                                entry: entry,
                                isSelected: selectedEntry?.id == entry.id,
                                archiveURL: url
                            )
                            .onTapGesture {
                                selectedEntry = entry
                            }
                        }
                    }
                }
                .overlay(
                    // Drop zone overlay
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isDragOver ? Color.accentColor : Color.clear, lineWidth: 3)
                        .background(isDragOver ? Color.accentColor.opacity(0.1) : Color.clear)
                        .padding(4)
                )
                .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
                    handleDrop(providers: providers)
                    return true
                }

                Divider()

                // Footer with stats
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
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Self.listArchiveContents(url: archiveURL)

            DispatchQueue.main.async {
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

    private static func listArchiveContents(url: URL) -> Result<[ArchiveEntry], Error> {
        let ext = url.pathExtension.lowercased()

        // Use different tools based on archive type
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
            // Try zip first
            process.arguments = ["unzip", "-l", url.path]
        }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return .failure(NSError(domain: "Archive", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not read archive"]))
            }

            let entries = parseArchiveOutput(output: output, type: ext)
            return .success(entries)
        } catch {
            return .failure(error)
        }
    }

    private static func parseArchiveOutput(output: String, type: String) -> [ArchiveEntry] {
        var entries: [ArchiveEntry] = []
        let lines = output.components(separatedBy: .newlines)

        switch type {
        case "zip":
            // Format: Length Date Time Name
            // Skip header and footer lines
            var inFileList = false
            for line in lines {
                if line.contains("--------") {
                    inFileList = !inFileList
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
            // Format: -rw-r--r-- user/group size date time name
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
            // Generic parsing - just show lines
            for line in lines where !line.isEmpty {
                entries.append(ArchiveEntry(path: line, name: line, size: 0, isDirectory: false, compressedSize: nil))
            }
        }

        return entries
    }

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, error in
                guard let data = data as? Data,
                      let fileURL = URL(dataRepresentation: data, relativeTo: nil) else { return }

                DispatchQueue.main.async {
                    addFileToArchive(fileURL: fileURL)
                }
            }
        }
    }

    private func addFileToArchive(fileURL: URL) {
        let ext = url.pathExtension.lowercased()

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.currentDirectoryURL = fileURL.deletingLastPathComponent()

            switch ext {
            case "zip":
                process.arguments = ["zip", "-r", url.path, fileURL.lastPathComponent]
            case "tar":
                process.arguments = ["tar", "-rf", url.path, fileURL.lastPathComponent]
            default:
                return // Not supported for other formats
            }

            try? process.run()
            process.waitUntilExit()

            DispatchQueue.main.async {
                loadArchive() // Refresh
            }
        }
    }
}

struct ArchiveEntryRow: View {
    let entry: ArchiveEntry
    let isSelected: Bool
    let archiveURL: URL
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: entry.isDirectory ? "folder.fill" : iconForFile)
                .font(.system(size: 14))
                .foregroundColor(entry.isDirectory ? .blue : .secondary)
                .frame(width: 20)

            Text(entry.name)
                .font(.system(size: 12))
                .lineLimit(1)
                .frame(minWidth: 150, alignment: .leading)

            Spacer()

            Text(entry.isDirectory ? "--" : entry.displaySize)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            isSelected ? Color.accentColor :
            (isHovered ? Color(NSColor.selectedContentBackgroundColor).opacity(0.2) : Color.clear)
        )
        .foregroundColor(isSelected ? .white : .primary)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .onDrag {
            // Extract file to temp and provide for drag
            let tempURL = extractToTemp()
            if let url = tempURL {
                return NSItemProvider(object: url as NSURL)
            }
            return NSItemProvider()
        }
    }

    private var iconForFile: String {
        let ext = URL(fileURLWithPath: entry.path).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "gif", "webp", "heic": return "photo"
        case "pdf": return "doc.richtext"
        case "txt", "md": return "doc.text"
        case "zip", "tar", "gz", "rar": return "doc.zipper"
        case "mp3", "wav", "m4a": return "waveform"
        case "mp4", "mov", "avi": return "film"
        default: return "doc"
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
            process.arguments = ["unzip", "-o", archiveURL.path, entry.path]
        case "tar", "tgz", "gz", "bz2", "xz":
            process.arguments = ["tar", "-xf", archiveURL.path, entry.path]
        default:
            return nil
        }

        do {
            try process.run()
            process.waitUntilExit()

            let extractedURL = tempDir.appendingPathComponent(entry.path)
            if FileManager.default.fileExists(atPath: extractedURL.path) {
                return extractedURL
            }
        } catch {
            print("Extract error: \(error)")
        }

        return nil
    }
}
