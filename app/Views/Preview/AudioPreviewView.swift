import SwiftUI
import AVFoundation
import AppKit

struct AudioPreviewView: View {
    let url: URL
    var manager: FileExplorerManager?
    @StateObject private var player = AudioPlayerManager()
    @ObservedObject private var settings = AppSettings.shared

    // Sibling audio files in the current folder + the track playing right now.
    // Kept internal to the preview so browsing tracks does not move the file selection.
    @State private var playlist: [URL] = []
    @State private var currentURL: URL

    init(url: URL, manager: FileExplorerManager? = nil) {
        self.url = url
        self.manager = manager
        _currentURL = State(initialValue: url)
    }

    private var currentIndex: Int? {
        playlist.firstIndex { $0.standardizedFileURL == currentURL.standardizedFileURL }
    }
    private var hasPrev: Bool { (currentIndex ?? 0) > 0 }
    private var hasNext: Bool {
        guard let i = currentIndex else { return false }
        return i < playlist.count - 1
    }

    var body: some View {
        VStack(spacing: 0) {
            PreviewHeader(title: "Audio preview", icon: "music.note", color: .pink)
            Divider()

            VStack(spacing: 12) {
                // Album art - only show if file has artwork
                if let artwork = player.artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 120, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // Track info
                VStack(spacing: 2) {
                    Text(player.title ?? url.deletingPathExtension().lastPathComponent)
                        .textStyle(.default, weight: .semibold)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)

                    if let artist = player.artist {
                        Text(artist)
                            .textStyle(.small)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                // Progress bar
                VStack(spacing: 2) {
                    Slider(value: $player.currentTime, in: 0...max(player.duration, 1)) { editing in
                        if !editing {
                            player.seek(to: player.currentTime)
                        }
                    }
                    .accentColor(.pink)

                    HStack {
                        Text(formatTime(player.currentTime))
                            .textStyle(.small, mono: true)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(formatTime(player.duration))
                            .textStyle(.small, mono: true)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 16)

                // Controls
                HStack(spacing: 20) {
                    Button(action: { goToPrevious() }) {
                        Image(systemName: "backward.end.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!hasPrev)
                    .opacity(hasPrev ? 1 : 0.3)
                    .help("Previous track")

                    Button(action: { player.skipBackward() }) {
                        Image(systemName: "gobackward.10")
                            .font(.system(size: 18))
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)

                    Button(action: { player.togglePlayPause() }) {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.pink)
                    }
                    .buttonStyle(.plain)

                    Button(action: { player.skipForward() }) {
                        Image(systemName: "goforward.10")
                            .font(.system(size: 18))
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)

                    Button(action: { goToNext() }) {
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!hasNext)
                    .opacity(hasNext ? 1 : 0.3)
                    .help("Next track")
                }

                Toggle(isOn: $settings.audioAutoNext) {
                    Text("Autoplay next")
                        .textStyle(.small)
                }
                .toggleStyle(.checkbox)

                // Volume
                HStack(spacing: 6) {
                    Image(systemName: "speaker.fill")
                        .textStyle(.small)
                        .foregroundColor(.secondary)

                    Slider(value: $player.volume, in: 0...1)
                        .frame(width: 80)
                        .accentColor(.secondary)

                    Image(systemName: "speaker.wave.3.fill")
                        .textStyle(.small)
                        .foregroundColor(.secondary)
                }

                // Crop controls - always visible when duration is known
                if player.duration > 0 {
                    Divider()
                        .padding(.vertical, 8)

                    HStack(spacing: 12) {
                        let canCutStart = player.currentTime > 1
                        let canCutEnd = player.currentTime > 0 && player.currentTime < player.duration - 1

                        // Left button
                        Button(action: {
                            Task {
                                await player.cropFromStart(url: url, to: player.currentTime)
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "backward.end.fill")
                                    .textStyle(.small)
                                Text("Remove start")
                                    .textStyle(.small, weight: .medium)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(canCutStart ? Color.orange : Color(NSColor.controlBackgroundColor))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(canCutStart ? Color.orange : Color.gray.opacity(0.4), lineWidth: 1)
                            )
                            .foregroundColor(canCutStart ? .white : .secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(!canCutStart)
                        .help("Remove audio from start to current position")

                        // Center text
                        VStack(spacing: 2) {
                            HStack(spacing: 4) {
                                Image(systemName: "scissors")
                                    .textStyle(.small)
                                    .foregroundColor(.orange)
                                Text("TRIM")
                                    .textStyle(.small, weight: .bold)
                                    .foregroundColor(.primary)
                            }
                            Text("Seek & trim")
                                .textStyle(.small)
                                .foregroundColor(.secondary)
                        }
                        .frame(minWidth: 60)

                        // Right button
                        Button(action: {
                            Task {
                                await player.cropToEnd(url: url, from: player.currentTime)
                            }
                        }) {
                            HStack(spacing: 4) {
                                Text("Remove end")
                                    .textStyle(.small, weight: .medium)
                                Image(systemName: "forward.end.fill")
                                    .textStyle(.small)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(canCutEnd ? Color.orange : Color(NSColor.controlBackgroundColor))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(canCutEnd ? Color.orange : Color.gray.opacity(0.4), lineWidth: 1)
                            )
                            .foregroundColor(canCutEnd ? .white : .secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(!canCutEnd)
                        .help("Remove audio from current position to end")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(NSColor.controlBackgroundColor))
                    )

                    if player.isCropping {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.6)
                            Text("Processing...")
                                .textStyle(.small)
                                .foregroundColor(.secondary)
                        }
                    }

                    if let cropMessage = player.cropMessage {
                        Text(cropMessage)
                            .textStyle(.small, weight: .medium)
                            .foregroundColor(player.cropSuccess ? .green : .red)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            currentURL = url
            player.load(url: currentURL)
            Task { await loadPlaylist(for: url) }
        }
        .onDisappear {
            player.stop()
        }
        .onChange(of: url) { newURL in
            // External selection changed - reset to that track without auto-playing
            currentURL = newURL
            player.load(url: newURL)
            Task { await loadPlaylist(for: newURL) }
        }
        .onChange(of: player.finishTick) { _ in
            if settings.audioAutoNext {
                goToNext()
            }
        }
    }

    // MARK: - Playlist navigation

    /// Audio siblings in play order: the folder's current sort when a manager is
    /// present, otherwise the parent directory sorted like Finder. The disk walk
    /// (only needed without a manager) runs off the main thread.
    private func loadPlaylist(for base: URL) async {
        let exts = PreviewType.audioExtensions

        if let manager {
            let urls = manager.files
                .map(\.url)
                .filter { exts.contains($0.pathExtension.lowercased()) }
            if !urls.isEmpty {
                playlist = urls
                return
            }
        }

        let dir = base.deletingLastPathComponent()
        playlist = await Task.detached(priority: .userInitiated) { () -> [URL] in
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
            return contents
                .filter { exts.contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        }.value
    }

    private func goToPrevious() {
        guard let i = currentIndex, i > 0 else { return }
        play(playlist[i - 1])
    }

    private func goToNext() {
        guard let i = currentIndex, i < playlist.count - 1 else { return }
        play(playlist[i + 1])
    }

    private func play(_ newURL: URL) {
        currentURL = newURL
        player.load(url: newURL)
        player.play()
    }

}

@MainActor
class AudioPlayerManager: ObservableObject {
    private var player: AVAudioPlayer?
    private var timer: Timer?

    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    // Bumped each time a track finishes on its own so the view can auto-advance
    @Published var finishTick = 0
    @Published var volume: Float = 0.8 {
        didSet {
            player?.volume = volume
        }
    }

    // Metadata
    @Published var title: String?
    @Published var artist: String?
    @Published var album: String?
    @Published var artwork: NSImage?

    func load(url: URL) {
        stop()

        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
            player?.volume = volume
            duration = player?.duration ?? 0

            // Load metadata
            loadMetadata(from: url)
        } catch {
            ToastManager.shared.showError("Error loading audio: \(error.localizedDescription)")
        }
    }

    private func loadMetadata(from url: URL) {
        let asset = AVAsset(url: url)

        Task {
            // Reset metadata
            self.title = nil
            self.artist = nil
            self.album = nil
            self.artwork = nil

            // Load metadata asynchronously
            if let metadata = try? await asset.load(.commonMetadata) {
                for item in metadata {
                    if let key = item.commonKey {
                        switch key {
                        case .commonKeyTitle:
                            self.title = try? await item.load(.stringValue)
                        case .commonKeyArtist:
                            self.artist = try? await item.load(.stringValue)
                        case .commonKeyAlbumName:
                            self.album = try? await item.load(.stringValue)
                        case .commonKeyArtwork:
                            if let data = try? await item.load(.dataValue) {
                                self.artwork = NSImage(data: data)
                            }
                        default:
                            break
                        }
                    }
                }
            }
        }
    }

    func togglePlayPause() {
        guard let player else { return }

        if isPlaying {
            player.pause()
            stopTimer()
        } else {
            player.play()
            startTimer()
        }
        isPlaying = player.isPlaying
    }

    /// Start playback from the current position (used by prev/next and auto-advance).
    func play() {
        guard let player else { return }
        player.play()
        isPlaying = player.isPlaying
        startTimer()
    }

    func stop() {
        player?.stop()
        stopTimer()
        isPlaying = false
        currentTime = 0
    }

    func seek(to time: Double) {
        player?.currentTime = time
    }

    func skipForward() {
        guard let player else { return }
        let newTime = min(player.currentTime + 10, player.duration)
        player.currentTime = newTime
        currentTime = newTime
    }

    func skipBackward() {
        guard let player else { return }
        let newTime = max(player.currentTime - 10, 0)
        player.currentTime = newTime
        currentTime = newTime
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime

                // Check if playback finished
                if !player.isPlaying && self.isPlaying {
                    self.isPlaying = false
                    self.currentTime = self.duration
                    self.stopTimer()
                    self.finishTick += 1
                }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Crop functionality

    @Published var isCropping = false
    @Published var cropMessage: String?
    @Published var cropSuccess = false

    /// Cut from start to specified time (keep audio from `to` to end)
    func cropFromStart(url: URL, to endTime: Double) async {
        await cropAudio(url: url, startTime: endTime, endTime: nil)
    }

    /// Cut from specified time to end (keep audio from start to `from`)
    func cropToEnd(url: URL, from startTime: Double) async {
        await cropAudio(url: url, startTime: 0, endTime: startTime)
    }

    private func cropAudio(url: URL, startTime: Double, endTime: Double?) async {
        isCropping = true
        cropMessage = nil
        cropSuccess = false

        // Stop playback
        stop()

        // Check if ffmpeg is available (path probe + `which` fallback run off main)
        let ffmpegPath = await Task.detached(priority: .userInitiated) { Self.findFFmpeg() }.value
        guard let ffmpeg = ffmpegPath else {
            cropMessage = "ffmpeg not found. Install with: brew install ffmpeg"
            isCropping = false
            return
        }

        let ext = url.pathExtension
        let baseName = url.deletingPathExtension().lastPathComponent
        let parentDir = url.deletingLastPathComponent()
        let tempOutput = parentDir.appendingPathComponent("\(baseName)_trimmed.\(ext)")

        var args = ["-i", url.path, "-y"]

        if let end = endTime {
            args += ["-t", String(format: "%.3f", end)]
        } else {
            args += ["-ss", String(format: "%.3f", startTime)]
        }

        args += ["-c", "copy", tempOutput.path]

        let result = await Task.detached { () -> (status: Int32, error: String) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ffmpeg)
            process.arguments = args
            let errorPipe = Pipe()
            process.standardError = errorPipe

            do {
                try process.run()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let errorString = String(data: errorData, encoding: .utf8) ?? ""
                return (process.terminationStatus, errorString)
            } catch {
                return (-1, error.localizedDescription)
            }
        }.value

        if result.status == 0 {
            do {
                let backup = parentDir.appendingPathComponent("\(baseName)_original.\(ext)")
                try FileManager.default.moveItem(at: url, to: backup)
                try FileManager.default.moveItem(at: tempOutput, to: url)
                try? FileManager.default.removeItem(at: backup)

                cropSuccess = true
                cropMessage = "Trimmed successfully!"
                load(url: url)
            } catch {
                cropMessage = "Error: \(error.localizedDescription)"
            }
        } else if result.status == -1 {
            cropMessage = "Error: \(result.error)"
        } else {
            cropMessage = "Error: \(String(result.error.prefix(100)))"
        }

        isCropping = false
    }

    nonisolated private static func findFFmpeg() -> String? {
        let paths = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]

        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["ffmpeg"]

        let pipe = Pipe()
        process.standardOutput = pipe

        try? process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty {
                return path
            }
        }

        return nil
    }
}
