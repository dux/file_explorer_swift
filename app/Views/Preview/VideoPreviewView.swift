import SwiftUI
import AVKit
import AppKit

struct VideoPreviewView: View {
    let url: URL
    @StateObject private var playerManager = VideoPlayerManager()

    var body: some View {
        VStack(spacing: 0) {
            PreviewHeader(title: "Video preview", icon: "film.fill", color: .orange)
            Divider()

            ZStack {
                // Video player
                VideoPlayerRepresentable(player: playerManager.player)
                    .background(Color.black)

                // Play button overlay when paused
                if !playerManager.isPlaying {
                    Button(action: { playerManager.togglePlayPause() }) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 64))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }

                // Controls overlay at bottom
                VStack {
                    Spacer()

                    VStack(spacing: 8) {
                        if playerManager.shouldShowSubtitleSearch {
                            SubtitleSearchPanel(
                                subtitleURL: playerManager.subtitleURL,
                                query: $playerManager.subtitleSearchQuery,
                                results: playerManager.subtitleSearchResults,
                                totalCount: playerManager.subtitles.count,
                                isLoading: playerManager.isLoadingSubtitles,
                                status: playerManager.subtitleStatus,
                                onSelect: { cue in
                                    playerManager.seek(to: cue.startTime)
                                    playerManager.currentTime = cue.startTime
                                }
                            )
                        }

                        // Progress bar
                        Slider(value: $playerManager.currentTime, in: 0...max(playerManager.duration, 1)) { editing in
                            if editing {
                                playerManager.isSeeking = true
                            } else {
                                playerManager.seek(to: playerManager.currentTime)
                                playerManager.isSeeking = false
                            }
                        }
                        .accentColor(.orange)

                        // Controls row
                        HStack {
                            Text(formatTime(playerManager.currentTime))
                                .textStyle(.small, mono: true)
                                .foregroundColor(.white)

                            Spacer()

                            HStack(spacing: 20) {
                                Button(action: { playerManager.skipBackward() }) {
                                    Image(systemName: "gobackward.10")
                                        .font(.system(size: 18))
                                        .foregroundColor(.white)
                                }
                                .buttonStyle(.plain)

                                Button(action: { playerManager.togglePlayPause() }) {
                                    Image(systemName: playerManager.isPlaying ? "pause.fill" : "play.fill")
                                        .font(.system(size: 22))
                                        .foregroundColor(.white)
                                }
                                .buttonStyle(.plain)

                                Button(action: { playerManager.skipForward() }) {
                                    Image(systemName: "goforward.10")
                                        .font(.system(size: 18))
                                        .foregroundColor(.white)
                                }
                                .buttonStyle(.plain)
                            }

                            Spacer()

                            HStack(spacing: 8) {
                                Image(systemName: playerManager.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                    .textStyle(.small)
                                    .foregroundColor(.white)
                                    .onTapGesture {
                                        playerManager.toggleMute()
                                    }

                                Slider(value: $playerManager.volume, in: 0...1)
                                    .frame(width: 60)
                                    .accentColor(.white)

                                Text(formatTime(playerManager.duration))
                                    .textStyle(.small, mono: true)
                                    .foregroundColor(.white)
                            }
                        }

                        // Trim controls
                        if playerManager.duration > 0 {
                            HStack(spacing: 12) {
                                Text("Trim:")
                                    .textStyle(.small)
                                    .foregroundColor(.white.opacity(0.7))

                                Button(action: {
                                    Task {
                                        await cropVideo(url: url, keepFrom: playerManager.currentTime, keepTo: nil)
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "scissors")
                                        Text("Cut start")
                                    }
                                    .textStyle(.small)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.orange.opacity(playerManager.currentTime > 1 ? 0.8 : 0.3))
                                    .foregroundColor(.white)
                                    .cornerRadius(4)
                                }
                                .buttonStyle(.plain)
                                .disabled(playerManager.currentTime <= 1 || playerManager.isCropping)

                                Button(action: {
                                    Task {
                                        await cropVideo(url: url, keepFrom: 0, keepTo: playerManager.currentTime)
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "scissors")
                                        Text("Cut end")
                                    }
                                    .textStyle(.small)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.orange.opacity(playerManager.currentTime > 0 && playerManager.currentTime < playerManager.duration - 1 ? 0.8 : 0.3))
                                    .foregroundColor(.white)
                                    .cornerRadius(4)
                                }
                                .buttonStyle(.plain)
                                .disabled(playerManager.currentTime <= 0 || playerManager.currentTime >= playerManager.duration - 1 || playerManager.isCropping)

                                if playerManager.isCropping {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    Text("Processing...")
                                        .textStyle(.small)
                                        .foregroundColor(.white.opacity(0.7))
                                }

                                if let msg = playerManager.cropMessage {
                                    Text(msg)
                                        .textStyle(.small)
                                        .foregroundColor(playerManager.cropSuccess ? .green : .red)
                                }

                                Spacer()
                            }
                        }
                    }
                    .padding(12)
                    .background(
                        LinearGradient(
                            colors: [Color.clear, Color.black.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }
        }
        .onAppear {
            playerManager.load(url: url)
        }
        .onDisappear {
            playerManager.pause()
        }
        .onChange(of: url) { newURL in
            playerManager.load(url: newURL)
        }
    }

    private func cropVideo(url: URL, keepFrom: Double, keepTo: Double?) async {
        if let endTime = keepTo {
            await playerManager.cropToEnd(url: url, at: endTime)
        } else {
            await playerManager.cropFromStart(url: url, at: keepFrom)
        }
    }

}

struct SubtitleSearchPanel: View {
    let subtitleURL: URL?
    @Binding var query: String
    let results: [SubtitleCue]
    let totalCount: Int
    let isLoading: Bool
    let status: String?
    let onSelect: (SubtitleCue) -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "captions.bubble")
                    .textStyle(.small)
                    .foregroundColor(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text(subtitleURL?.lastPathComponent ?? "Subtitles")
                        .textStyle(.small, weight: .medium)
                        .foregroundColor(.white)
                        .lineLimit(1)

                    if totalCount > 0 {
                        Text("\(totalCount) lines")
                            .textStyle(.small)
                            .foregroundColor(.white.opacity(0.65))
                    }
                }

                Spacer()

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else if !query.isEmpty {
                    Button(action: { query = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .textStyle(.small)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
            }

            if totalCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .textStyle(.small)
                        .foregroundColor(.white.opacity(0.65))

                    TextField("Search subtitles", text: $query)
                        .textFieldStyle(.plain)
                        .textStyle(.small)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.12))
                .cornerRadius(5)

                if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if results.isEmpty {
                        Text("No subtitle matches")
                            .textStyle(.small)
                            .foregroundColor(.white.opacity(0.65))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ScrollView {
                            VStack(spacing: 2) {
                                ForEach(results) { cue in
                                    Button(action: { onSelect(cue) }) {
                                        HStack(alignment: .top, spacing: 8) {
                                            Text(formatTime(cue.startTime))
                                                .textStyle(.small, mono: true)
                                                .foregroundColor(.orange)
                                                .frame(width: 48, alignment: .leading)

                                            Text(cue.text)
                                                .textStyle(.small)
                                                .foregroundColor(.white)
                                                .lineLimit(2)
                                                .multilineTextAlignment(.leading)

                                            Spacer(minLength: 0)
                                        }
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 5)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .frame(maxHeight: 110)
                    }
                }
            } else if let status {
                Text(status)
                    .textStyle(.small)
                    .foregroundColor(.white.opacity(0.65))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.55))
        .cornerRadius(6)
    }
}

struct VideoPlayerRepresentable: NSViewRepresentable {
    let player: AVPlayer?

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.player = player
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
    }
}

struct SubtitleCue: Identifiable, Hashable, Sendable {
    let id: Int
    let startTime: Double
    let endTime: Double
    let text: String

    var searchText: String {
        text.lowercased()
    }
}

@MainActor
class VideoPlayerManager: ObservableObject {
    @Published var player: AVPlayer?
    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var volume: Float = 1.0 {
        didSet {
            player?.volume = volume
        }
    }
    @Published var isMuted = false
    @Published var isSeeking = false
    @Published var subtitleURL: URL?
    @Published var subtitles: [SubtitleCue] = []
    @Published var subtitleSearchQuery = ""
    @Published var subtitleStatus: String?
    @Published var isLoadingSubtitles = false

    private var timeObserver: Any?
    private var subtitleLoadTask: Task<Void, Never>?

    var shouldShowSubtitleSearch: Bool {
        subtitleURL != nil || isLoadingSubtitles || subtitleStatus != nil
    }

    var subtitleSearchResults: [SubtitleCue] {
        let terms = subtitleSearchQuery
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })

        guard !terms.isEmpty else { return [] }

        return Array(subtitles.lazy.filter { cue in
            terms.allSatisfy { cue.searchText.contains($0) }
        }.prefix(50))
    }

    func load(url: URL) {
        // Clean up previous player
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }

        let playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)
        player?.volume = volume
        loadSubtitles(for: url)

        // Get duration
        Task {
            if let duration = try? await playerItem.asset.load(.duration) {
                self.duration = CMTimeGetSeconds(duration)
            }
        }

        // Add time observer
        timeObserver = player?.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self, !self.isSeeking else { return }
                self.currentTime = CMTimeGetSeconds(time)
            }
        }

        // Observe when playback ends
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: playerItem, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.isPlaying = false
                self?.player?.seek(to: .zero)
                self?.currentTime = 0
            }
        }
    }

    func togglePlayPause() {
        guard let player else { return }

        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func seek(to time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime)
    }

    func skipForward() {
        let newTime = min(currentTime + 10, duration)
        seek(to: newTime)
        currentTime = newTime
    }

    func skipBackward() {
        let newTime = max(currentTime - 10, 0)
        seek(to: newTime)
        currentTime = newTime
    }

    func toggleMute() {
        isMuted.toggle()
        player?.isMuted = isMuted
    }

    private func loadSubtitles(for videoURL: URL) {
        subtitleLoadTask?.cancel()
        subtitleLoadTask = nil
        subtitleURL = nil
        subtitles = []
        subtitleSearchQuery = ""
        subtitleStatus = nil
        isLoadingSubtitles = false

        let srtURL = Self.englishSubtitleURL(for: videoURL)
        guard FileManager.default.fileExists(atPath: srtURL.path) else {
            return
        }

        subtitleURL = srtURL
        isLoadingSubtitles = true

        subtitleLoadTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                Result { try Self.loadSubtitleCues(from: srtURL) }
            }.value

            guard !Task.isCancelled, let self else { return }

            self.isLoadingSubtitles = false

            switch result {
            case .success(let cues):
                self.subtitles = cues
                self.subtitleStatus = cues.isEmpty ? "No subtitle lines found" : nil
            case .failure(let error):
                self.subtitles = []
                self.subtitleStatus = "Could not read subtitles: \(error.localizedDescription)"
            }
        }
    }

    nonisolated private static func englishSubtitleURL(for videoURL: URL) -> URL {
        let baseName = videoURL.deletingPathExtension().lastPathComponent
        return videoURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(baseName).en.srt")
    }

    nonisolated private static func loadSubtitleCues(from url: URL) throws -> [SubtitleCue] {
        let data = try Data(contentsOf: url)
        let encodings: [String.Encoding] = [
            .utf8,
            .utf16,
            .utf16LittleEndian,
            .utf16BigEndian,
            .windowsCP1250,
            .isoLatin1
        ]

        let contents = encodings.lazy.compactMap { String(data: data, encoding: $0) }.first ?? ""
        return parseSRT(contents)
    }

    nonisolated private static func parseSRT(_ contents: String) -> [SubtitleCue] {
        let normalized = contents
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let blocks = normalized.components(separatedBy: "\n\n")
        var cues: [SubtitleCue] = []

        for block in blocks {
            let lines = block
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)

            guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }) else {
                continue
            }

            let timingParts = lines[timingIndex].components(separatedBy: "-->")
            guard timingParts.count == 2,
                  let startTime = parseSubtitleTime(timingParts[0]),
                  let endTime = parseSubtitleTime(timingParts[1]) else {
                continue
            }

            let text = lines
                .dropFirst(timingIndex + 1)
                .map(stripSubtitleMarkup)
                .joined(separator: " ")
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !text.isEmpty else { continue }

            cues.append(SubtitleCue(
                id: cues.count,
                startTime: startTime,
                endTime: endTime,
                text: text
            ))
        }

        return cues
    }

    nonisolated private static func parseSubtitleTime(_ value: String) -> Double? {
        let cleaned = value
            .components(separatedBy: .whitespaces)
            .first?
            .replacingOccurrences(of: ",", with: ".")

        guard let cleaned else { return nil }

        let parts = cleaned.split(separator: ":")
        guard parts.count == 3,
              let hours = Double(parts[0]),
              let minutes = Double(parts[1]),
              let seconds = Double(parts[2]) else {
            return nil
        }

        return (hours * 3600) + (minutes * 60) + seconds
    }

    nonisolated private static func stripSubtitleMarkup(_ line: String) -> String {
        line
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Crop functionality

    @Published var isCropping = false
    @Published var cropMessage: String?
    @Published var cropSuccess = false

    /// Cut from start to specified time (keep from `at` to end)
    func cropFromStart(url: URL, at startTime: Double) async {
        await cropMedia(url: url, startTime: startTime, endTime: nil)
    }

    /// Cut from specified time to end (keep from start to `at`)
    func cropToEnd(url: URL, at endTime: Double) async {
        await cropMedia(url: url, startTime: 0, endTime: endTime)
    }

    private func cropMedia(url: URL, startTime: Double, endTime: Double?) async {
        isCropping = true
        cropMessage = nil
        cropSuccess = false

        pause()

        guard let ffmpeg = Self.findFFmpeg() else {
            cropMessage = "ffmpeg not found. Install: brew install ffmpeg"
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
                cropMessage = "Trimmed!"
                load(url: url)
            } catch {
                cropMessage = "Error: \(error.localizedDescription)"
            }
        } else if result.status == -1 {
            cropMessage = "Error: \(result.error)"
        } else {
            cropMessage = "Error: \(String(result.error.prefix(50)))"
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
