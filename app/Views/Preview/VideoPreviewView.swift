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
                                .font(.system(size: 12, design: .monospaced))
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
                                    .font(.system(size: 12))
                                    .foregroundColor(.white)
                                    .onTapGesture {
                                        playerManager.toggleMute()
                                    }

                                Slider(value: $playerManager.volume, in: 0...1)
                                    .frame(width: 60)
                                    .accentColor(.white)

                                Text(formatTime(playerManager.duration))
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(.white)
                            }
                        }

                        // Trim controls
                        if playerManager.duration > 0 {
                            HStack(spacing: 12) {
                                Text("Trim:")
                                    .font(.system(size: 12))
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
                                    .font(.system(size: 12))
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
                                    .font(.system(size: 12))
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
                                        .font(.system(size: 10))
                                        .foregroundColor(.white.opacity(0.7))
                                }

                                if let msg = playerManager.cropMessage {
                                    Text(msg)
                                        .font(.system(size: 10))
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

    private func formatTime(_ time: Double) -> String {
        guard time.isFinite && time >= 0 else { return "0:00" }
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
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

    private var timeObserver: Any?

    func load(url: URL) {
        // Clean up previous player
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }

        let playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)
        player?.volume = volume

        // Get duration
        Task {
            if let duration = try? await playerItem.asset.load(.duration) {
                self.duration = CMTimeGetSeconds(duration)
            }
        }

        // Add time observer
        timeObserver = player?.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self = self, !self.isSeeking else { return }
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
        guard let player = player else { return }

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
