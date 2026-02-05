import SwiftUI
import Foundation

struct YouTubeFormat: Identifiable, Hashable {
    let id: String
    let formatId: String
    let ext: String
    let resolution: String
    let filesize: String
    let description: String
    let isAudioOnly: Bool
    let isVideoOnly: Bool
}

struct YouTubeDownloadSheet: View {
    let downloadPath: URL
    let onComplete: () -> Void

    @Environment(\.dismiss) var dismiss
    @State private var urlText: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var videoTitle: String?
    @State private var formats: [YouTubeFormat] = []
    @State private var selectedFormat: YouTubeFormat?
    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0
    @State private var downloadStatus: String = ""
    @State private var isPlaylist = false
    @State private var playlistTitle: String?
    @State private var playlistCount: Int = 0
    @State private var downloadedFileCount: Int = 0
    @State private var downloadedTotalSize: String = ""
    @State private var folderSizeTimer: Timer?
    @State private var currentCommand: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.red)
                Text("YouTube Download")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Content
            VStack(spacing: 16) {
                // Usage info
                VStack(alignment: .leading, spacing: 4) {
                    Text("• Single video: pick format (quality/audio)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("• Playlist (list= in URL): downloads all as audio")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)

                // URL input
                VStack(alignment: .leading, spacing: 6) {
                    Text("Video URL")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)

                    HStack {
                        TextField("https://youtube.com/watch?v=...", text: $urlText)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                fetchFormats()
                            }

                        Button(action: { pasteFromClipboard() }) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 14))
                        }
                        .buttonStyle(.bordered)
                        .help("Paste from clipboard")

                        Button(action: { fetchFormats() }) {
                            if isLoading {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Text("Fetch")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(urlText.isEmpty || isLoading)
                    }
                }

                if let error = errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(10)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(6)
                }

                // Playlist info
                if isPlaylist, let title = playlistTitle {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "music.note.list")
                                .foregroundColor(.purple)
                            Text(title)
                                .font(.system(size: 14, weight: .medium))
                                .lineLimit(2)
                        }

                        Text("\(playlistCount) videos - will download as best audio")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)

                        Divider()

                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.blue)
                            Text("Playlist detected. Will download all videos as audio files.")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .padding(10)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(6)
                    }
                }

                // Video info & formats (single video only)
                if !isPlaylist, let title = videoTitle {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(title)
                            .font(.system(size: 14, weight: .medium))
                            .lineLimit(2)

                        Divider()

                        Text("Available Formats")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)

                        ScrollView {
                            VStack(spacing: 4) {
                                // Best combined (video + audio)
                                FormatSection(title: "Video + Audio", formats: formats.filter { !$0.isAudioOnly && !$0.isVideoOnly }, selectedFormat: $selectedFormat)

                                // Video only
                                FormatSection(title: "Video Only", formats: formats.filter { $0.isVideoOnly }, selectedFormat: $selectedFormat)

                                // Audio only
                                FormatSection(title: "Audio Only", formats: formats.filter { $0.isAudioOnly }, selectedFormat: $selectedFormat)
                            }
                        }
                        .frame(maxHeight: 300)
                    }
                }

                // Download progress
                if isDownloading {
                    VStack(spacing: 8) {
                        if isPlaylist {
                            // Playlist progress: show file count and total size
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Downloading...")
                                        .font(.system(size: 12, weight: .medium))
                                    Text("\(downloadedFileCount) files • \(downloadedTotalSize)")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.primary)
                                }
                                Spacer()
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        } else {
                            ProgressView(value: downloadProgress, total: 100)
                                .progressViewStyle(.linear)

                            Text(downloadStatus)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        // Show command
                        if !currentCommand.isEmpty {
                            Text(currentCommand)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                                .lineLimit(3)
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }

                Spacer()

                // Download path info
                HStack {
                    Image(systemName: "folder")
                        .foregroundColor(.secondary)
                    Text("Download to: \(downloadPath.path)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                }

                // Action buttons
                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)

                    Spacer()

                    Button(action: { startDownload() }) {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                            Text(isPlaylist ? "Download All Audio" : "Download")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled((!isPlaylist && selectedFormat == nil) || isDownloading || (isPlaylist && playlistTitle == nil))
                }
            }
            .padding()
        }
        .frame(width: 550, height: 550)
        .onAppear {
            pasteFromClipboard()
        }
    }

    private func pasteFromClipboard() {
        if let string = NSPasteboard.general.string(forType: .string),
           string.contains("youtube.com") || string.contains("youtu.be") {
            urlText = string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func checkIfPlaylist(_ url: String) -> Bool {
        return url.contains("list=") && !url.contains("&list=RD") // RD is radio/mix, not real playlist
    }

    private func fetchFormats() {
        guard !urlText.isEmpty else { return }

        isLoading = true
        errorMessage = nil
        videoTitle = nil
        playlistTitle = nil
        playlistCount = 0
        formats = []
        selectedFormat = nil
        isPlaylist = checkIfPlaylist(urlText)

        Task {
            do {
                if isPlaylist {
                    let result = try await getPlaylistInfo(url: urlText)
                    playlistTitle = result.title
                    playlistCount = result.count
                } else {
                    let result = try await getVideoInfo(url: urlText)
                    videoTitle = result.title
                    formats = result.formats
                    if let best = formats.first(where: { !$0.isAudioOnly && !$0.isVideoOnly }) {
                        selectedFormat = best
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func getPlaylistInfo(url: String) async throws -> (title: String, count: Int) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/yt-dlp")
        process.arguments = ["--flat-playlist", "-J", "--no-warnings", url]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()

        // Read data and wait in background thread - must read BEFORE waitUntilExit to avoid pipe buffer deadlock
        let data = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: result)
            }
        }

        guard process.terminationStatus == 0 else {
            let errorStr = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "YouTube", code: 1, userInfo: [NSLocalizedDescriptionKey: errorStr])
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "YouTube", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to parse response"])
        }

        let title = json["title"] as? String ?? "Unknown Playlist"
        let entries = json["entries"] as? [[String: Any]] ?? []

        return (title, entries.count)
    }

    private func getVideoInfo(url: String) async throws -> (title: String, formats: [YouTubeFormat]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/yt-dlp")
        process.arguments = ["-J", "--no-warnings", url]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()

        // Read data and wait in background thread - must read BEFORE waitUntilExit to avoid pipe buffer deadlock
        let data = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: result)
            }
        }

        guard process.terminationStatus == 0 else {
            let errorStr = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "YouTube", code: 1, userInfo: [NSLocalizedDescriptionKey: errorStr])
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "YouTube", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to parse response"])
        }

        let title = json["title"] as? String ?? "Unknown"
        var parsedFormats: [YouTubeFormat] = []

        if let formatsArray = json["formats"] as? [[String: Any]] {
            var seenDescriptions = Set<String>()

            for fmt in formatsArray {
                let formatId = fmt["format_id"] as? String ?? ""
                let ext = fmt["ext"] as? String ?? ""
                let resolution = fmt["resolution"] as? String ?? fmt["format_note"] as? String ?? ""
                let vcodec = fmt["vcodec"] as? String ?? "none"
                let acodec = fmt["acodec"] as? String ?? "none"

                let filesizeNum = fmt["filesize"] as? Int64 ?? fmt["filesize_approx"] as? Int64 ?? 0
                let filesize = filesizeNum > 0 ? ByteCountFormatter.string(fromByteCount: filesizeNum, countStyle: .file) : "?"

                let isAudioOnly = vcodec == "none" && acodec != "none"
                let isVideoOnly = vcodec != "none" && acodec == "none"

                // Get codec info for differentiation
                let vcodecShort = vcodec.components(separatedBy: ".").first ?? vcodec
                let acodecShort = acodec.components(separatedBy: ".").first ?? acodec

                let desc: String
                if isAudioOnly {
                    let abr = fmt["abr"] as? Double ?? 0
                    desc = "\(ext.uppercased()) • \(Int(abr))kbps • \(acodecShort) • \(filesize)"
                } else if isVideoOnly {
                    let fps = fmt["fps"] as? Int ?? 0
                    desc = "\(resolution) • \(ext.uppercased()) • \(fps)fps • \(vcodecShort) • \(filesize)"
                } else {
                    let fps = fmt["fps"] as? Int ?? 0
                    desc = "\(resolution) • \(ext.uppercased()) • \(fps)fps • \(vcodecShort)+\(acodecShort) • \(filesize)"
                }

                // Filter out storyboard, mhtml, and duplicate descriptions
                if ext != "mhtml" && !resolution.contains("storyboard") && !seenDescriptions.contains(desc) {
                    seenDescriptions.insert(desc)
                    parsedFormats.append(YouTubeFormat(
                        id: formatId,
                        formatId: formatId,
                        ext: ext,
                        resolution: resolution,
                        filesize: filesize,
                        description: desc,
                        isAudioOnly: isAudioOnly,
                        isVideoOnly: isVideoOnly
                    ))
                }
            }
        }

        // Sort: combined first by resolution, then video only, then audio
        parsedFormats.sort { f1, f2 in
            if f1.isAudioOnly != f2.isAudioOnly {
                return !f1.isAudioOnly
            }
            if f1.isVideoOnly != f2.isVideoOnly {
                return !f1.isVideoOnly
            }
            return extractResolutionHeight(f1.resolution) > extractResolutionHeight(f2.resolution)
        }

        return (title, parsedFormats)
    }

    private func extractResolutionHeight(_ res: String) -> Int {
        // Extract number from strings like "1080p", "720p", "1920x1080"
        let numbers = res.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
        if let last = numbers.last, let height = Int(last) {
            return height
        }
        return 0
    }

    private func startDownload() {
        isDownloading = true
        downloadProgress = 0
        downloadStatus = "Starting download..."

        Task {
            if isPlaylist {
                await downloadPlaylistAudio()
            } else {
                guard let format = selectedFormat else { return }
                await downloadVideo(formatId: format.formatId)
            }
        }
    }

    private func downloadPlaylistAudio() async {
        // Snapshot initial file count to track new files
        let initialFileCount = countFilesInFolder()

        let args = [
            "--ffmpeg-location", "/opt/homebrew/bin/ffmpeg",
            "-f", "bestaudio",
            "-x", "--audio-format", "m4a",
            "-o", "%(playlist_index)02d - %(title)s.%(ext)s",
            urlText
        ]

        // Start folder size monitoring on main thread
        await MainActor.run {
            downloadedFileCount = 0
            downloadedTotalSize = "0 KB"
            currentCommand = "cd \"\(downloadPath.path)\" && yt-dlp " + args.map { $0.contains(" ") ? "\"\($0)\"" : $0 }.joined(separator: " ")
            startFolderSizeMonitoring(initialFileCount: initialFileCount)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/yt-dlp")
        process.currentDirectoryURL = downloadPath
        process.arguments = args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()

            // Wait in background to not block timer
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    process.waitUntilExit()
                    continuation.resume()
                }
            }

            await MainActor.run {
                stopFolderSizeMonitoring()
                updateFolderStats(initialFileCount: initialFileCount) // Final update

                // Consider success if any new files were downloaded
                let newFiles = downloadedFileCount
                if newFiles > 0 {
                    downloadStatus = "Downloaded \(newFiles) files!"
                    onComplete()

                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        dismiss()
                    }
                } else if process.terminationStatus == 0 {
                    downloadStatus = "Complete (no new files)"
                    onComplete()

                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        dismiss()
                    }
                } else {
                    errorMessage = "Download failed"
                    isDownloading = false
                }
            }
        } catch {
            await MainActor.run {
                stopFolderSizeMonitoring()
                errorMessage = error.localizedDescription
                isDownloading = false
            }
        }
    }

    private func countFilesInFolder() -> Int {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(at: downloadPath, includingPropertiesForKeys: nil) else { return 0 }
        return contents.filter { !$0.hasDirectoryPath }.count
    }

    @State private var initialFolderFileCount: Int = 0

    private func startFolderSizeMonitoring(initialFileCount: Int) {
        initialFolderFileCount = initialFileCount
        updateFolderStats(initialFileCount: initialFileCount)
        folderSizeTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [self] _ in
            Task { @MainActor in
                updateFolderStats(initialFileCount: initialFolderFileCount)
            }
        }
    }

    private func stopFolderSizeMonitoring() {
        folderSizeTimer?.invalidate()
        folderSizeTimer = nil
    }

    private func updateFolderStats(initialFileCount: Int) {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(at: downloadPath, includingPropertiesForKeys: [.fileSizeKey]) else { return }

        var totalSize: Int64 = 0
        var fileCount = 0

        for fileURL in contents {
            guard !fileURL.hasDirectoryPath else { continue }
            if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let size = resourceValues.fileSize {
                totalSize += Int64(size)
                fileCount += 1
            }
        }

        // Only count new files (files added since download started)
        downloadedFileCount = max(0, fileCount - initialFileCount)
        downloadedTotalSize = ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }

    private func downloadVideo(formatId: String) async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/yt-dlp")
        process.currentDirectoryURL = downloadPath
        process.arguments = [
            "-f", formatId,
            "--newline",
            "--progress",
            "-o", "%(title)s.%(ext)s",
            urlText
        ]

        // Build command for display
        let args = process.arguments ?? []
        await MainActor.run {
            currentCommand = "cd \"\(downloadPath.path)\" && yt-dlp " + args.map { $0.contains(" ") ? "\"\($0)\"" : $0 }.joined(separator: " ")
        }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()

            // Read output line by line for progress in a separate task
            let handle = pipe.fileHandleForReading
            Task {
                for try await line in handle.bytes.lines {
                    await MainActor.run {
                        parseProgressLine(line)
                    }
                }
            }

            // Wait for process in background thread - don't block async context
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    process.waitUntilExit()
                    continuation.resume()
                }
            }

            await MainActor.run {
                if process.terminationStatus == 0 {
                    downloadProgress = 100
                    downloadStatus = "Download complete!"
                    onComplete()

                    // Close after short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        dismiss()
                    }
                } else {
                    errorMessage = "Download failed"
                    isDownloading = false
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isDownloading = false
            }
        }
    }

    private func parseProgressLine(_ line: String) {
        // Parse lines like: [download]  45.2% of 50.00MiB at 5.00MiB/s ETA 00:05
        if line.contains("%") {
            let parts = line.components(separatedBy: CharacterSet.whitespaces).filter { !$0.isEmpty }
            for part in parts {
                if part.hasSuffix("%"), let percent = Double(part.dropLast()) {
                    downloadProgress = percent
                    break
                }
            }
            downloadStatus = line.trimmingCharacters(in: .whitespaces)
        } else if line.contains("[download]") || line.contains("[Merger]") {
            downloadStatus = line.replacingOccurrences(of: "[download]", with: "").trimmingCharacters(in: .whitespaces)
        }
    }
}

struct FormatSection: View {
    let title: String
    let formats: [YouTubeFormat]
    @Binding var selectedFormat: YouTubeFormat?

    var body: some View {
        if !formats.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.top, 8)

                ForEach(formats.prefix(10)) { format in
                    FormatRow(format: format, isSelected: selectedFormat?.id == format.id)
                        .onTapGesture {
                            selectedFormat = format
                        }
                }
            }
        }
    }
}

struct FormatRow: View {
    let format: YouTubeFormat
    let isSelected: Bool

    var body: some View {
        HStack {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? .accentColor : .secondary)
                .font(.system(size: 14))

            Text(format.description)
                .font(.system(size: 12))
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(4)
        .contentShape(Rectangle())
    }
}
