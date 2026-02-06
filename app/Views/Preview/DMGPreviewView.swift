import SwiftUI
import UniformTypeIdentifiers

struct DMGEntry: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let name: String
    let size: Int64
    let isDirectory: Bool
    let isApp: Bool

    var displaySize: String {
        if isDirectory && !isApp {
            return "--"
        }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

// Manager to handle DMG mounts across the app
final class DMGMountManager: @unchecked Sendable {
    static let shared = DMGMountManager()
    private var mounts: [URL: String] = [:] // dmgURL -> mountPath
    private let queue = DispatchQueue(label: "dmg.mount.manager")

    func getMountPath(for dmgURL: URL) -> String? {
        queue.sync { mounts[dmgURL] }
    }

    func setMountPath(_ path: String, for dmgURL: URL) {
        queue.sync { mounts[dmgURL] = path }
    }

    func removeMountPath(for dmgURL: URL) {
        queue.sync { _ = mounts.removeValue(forKey: dmgURL) }
    }
}

struct DMGPreviewView: View {
    let url: URL
    @State private var entries: [DMGEntry] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedEntry: DMGEntry?
    @State private var mountPath: String?
    @State private var volumeName: String?
    @State private var dmgInfo: DMGInfo?

    struct DMGInfo {
        let format: String
        let compressedSize: Int64
        let totalSize: Int64
    }

    var body: some View {
        VStack(spacing: 0) {
            PreviewHeader(title: url.lastPathComponent, icon: "externaldrive.fill", color: .purple)
            Divider()

            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Mounting disk image...")
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
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Volume name header
                if let volName = volumeName {
                    HStack {
                        Image(systemName: "internaldrive")
                            .foregroundColor(.purple)
                        Text(volName)
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        if let info = dmgInfo {
                            Text(info.format)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    Divider()
                }

                // Column header
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
                .background(Color(NSColor.controlBackgroundColor).opacity(0.3))

                Divider()

                // File list
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(entries) { entry in
                            DMGEntryRow(
                                entry: entry,
                                isSelected: selectedEntry?.id == entry.id
                            )
                            .onTapGesture {
                                selectedEntry = entry
                            }
                            .onTapGesture(count: 2) {
                                openEntry(entry)
                            }
                        }
                    }
                }

                Divider()

                // Footer with stats
                HStack {
                    Text("\(entries.count) items")
                    Spacer()
                    if let info = dmgInfo {
                        Text("\(ByteCountFormatter.string(fromByteCount: info.compressedSize, countStyle: .file)) compressed")
                            .foregroundColor(.secondary)
                    }
                }
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
            }
        }
        .onAppear { mountAndLoad() }
        .onChange(of: url) { _ in mountAndLoad() }
        .onDisappear { unmount() }
    }

    private func mountAndLoad() {
        isLoading = true
        errorMessage = nil
        entries = []
        volumeName = nil

        let dmgURL = url
        Task.detached {
            let info = Self.getDMGInfo(for: dmgURL)
            await MainActor.run { self.dmgInfo = info }
            await self.mountDMG()
        }
    }

    nonisolated private static func getDMGInfo(for url: URL) -> DMGInfo? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["imageinfo", "-plist", url.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            if let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                let format = plist["Format Description"] as? String ?? "Unknown"
                var compressedSize: Int64 = 0
                var totalSize: Int64 = 0

                if let sizeInfo = plist["Size Information"] as? [String: Any] {
                    compressedSize = sizeInfo["Compressed Bytes"] as? Int64 ?? 0
                    totalSize = sizeInfo["Total Bytes"] as? Int64 ?? 0
                }

                return DMGInfo(format: format, compressedSize: compressedSize, totalSize: totalSize)
            }
        } catch {}
        return nil
    }

    private func mountDMG() async {
        let dmgURL = url
        let mountId = dmgURL.path.data(using: .utf8)!.base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .prefix(32)
        let mountPoint = "/tmp/dmg_preview_\(mountId)"

        // Check if already mounted by us
        if let existingMount = DMGMountManager.shared.getMountPath(for: dmgURL),
           FileManager.default.fileExists(atPath: existingMount) {
            await MainActor.run {
                self.mountPath = existingMount
                loadContents(from: existingMount)
            }
            return
        }

        // Run hdiutil attach off main thread
        let result = await Task.detached { () -> (status: Int32, data: Data, mountPoint: String) in
            try? FileManager.default.createDirectory(atPath: mountPoint, withIntermediateDirectories: true)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            process.arguments = [
                "attach",
                "-readonly",
                "-noverify",
                "-noautoopen",
                "-nobrowse",
                "-mountpoint", mountPoint,
                "-plist",
                dmgURL.path
            ]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                return (process.terminationStatus, data, mountPoint)
            } catch {
                return (-1, Data(), mountPoint)
            }
        }.value

        if result.status == 0 {
            var volName: String?
            if let plist = try? PropertyListSerialization.propertyList(from: result.data, format: nil) as? [String: Any],
               let entities = plist["system-entities"] as? [[String: Any]] {
                for entity in entities {
                    if let mountPointFromPlist = entity["mount-point"] as? String {
                        volName = URL(fileURLWithPath: mountPointFromPlist).lastPathComponent
                        break
                    }
                }
            }

            self.mountPath = result.mountPoint
            self.volumeName = volName ?? dmgURL.deletingPathExtension().lastPathComponent
            DMGMountManager.shared.setMountPath(result.mountPoint, for: dmgURL)
            loadContents(from: result.mountPoint)
        } else {
            let errorStr = String(data: result.data, encoding: .utf8) ?? "Mount failed"

            if errorStr.contains("password") || errorStr.contains("encrypted") {
                self.errorMessage = "Encrypted DMG - password required"
            } else {
                self.errorMessage = "Failed to mount: \(String(errorStr.prefix(100)))"
            }
            self.isLoading = false
        }
    }

    private func loadContents(from path: String) {
        let fileManager = FileManager.default
        var items: [DMGEntry] = []

        do {
            let contents = try fileManager.contentsOfDirectory(at: URL(fileURLWithPath: path),
                                                                includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey, .totalFileSizeKey])

            for fileURL in contents {
                // Skip hidden files except .app bundles hidden inside
                let name = fileURL.lastPathComponent
                if name.hasPrefix(".") { continue }

                let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey, .totalFileSizeKey])
                let isDirectory = resourceValues?.isDirectory ?? false
                let isApp = fileURL.pathExtension.lowercased() == "app"

                var size: Int64 = 0
                if isApp {
                    // Get total size of .app bundle
                    size = getDirectorySize(fileURL)
                } else if !isDirectory {
                    size = Int64(resourceValues?.fileSize ?? 0)
                }

                items.append(DMGEntry(
                    url: fileURL,
                    name: name,
                    size: size,
                    isDirectory: isDirectory,
                    isApp: isApp
                ))
            }

            // Sort: apps first, then folders, then files
            items.sort { a, b in
                if a.isApp != b.isApp { return a.isApp }
                if a.isDirectory != b.isDirectory { return a.isDirectory }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }

            entries = items
            isLoading = false
        } catch {
            errorMessage = "Failed to read contents"
            isLoading = false
        }
    }

    private func getDirectorySize(_ url: URL) -> Int64 {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }

        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalSize += Int64(size)
            }
        }
        return totalSize
    }

    private func openEntry(_ entry: DMGEntry) {
        NSWorkspace.shared.open(entry.url)
    }

    private func unmount() {
        guard let path = mountPath else { return }

        DMGMountManager.shared.removeMountPath(for: url)

        // Unmount in background
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            process.arguments = ["detach", path, "-quiet"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            try? process.run()
            process.waitUntilExit()

            // Clean up mount point directory
            try? FileManager.default.removeItem(atPath: path)
        }
    }
}

struct DMGEntryRow: View {
    let entry: DMGEntry
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path))
                .resizable()
                .frame(width: 22, height: 22)

            Text(entry.name)
                .font(.system(size: 14))
                .lineLimit(1)
                .foregroundColor(isSelected ? .white : .primary)

            Spacer()

            if !entry.isDirectory || entry.isApp {
                Text(entry.displaySize)
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary)
                    .frame(width: 60, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.trailing, 12)
        .padding(.vertical, 5)
        .background(isSelected ? Color.accentColor : Color.clear)
        .cornerRadius(4)
        .contentShape(Rectangle())
        .onDrag {
            NSItemProvider(object: entry.url as NSURL)
        }
    }
}
