import SwiftUI

enum ToastStyle {
    case info
    case error
}

@MainActor
class ToastManager: ObservableObject {
    static let shared = ToastManager()

    @Published var message: String = ""
    @Published var isShowing: Bool = false
    @Published var style: ToastStyle = .info

    private var hideTask: DispatchWorkItem?

    func show(_ message: String, duration: Double = 2.0) {
        showToast(message, style: .info, duration: duration)
    }

    func showError(_ message: String, duration: Double = 3.0) {
        showToast(message, style: .error, duration: duration)
    }

    private func showToast(_ message: String, style: ToastStyle, duration: Double) {
        hideTask?.cancel()

        self.message = message
        self.style = style
        withAnimation(.easeInOut(duration: 0.2)) {
            self.isShowing = true
        }

        let task = DispatchWorkItem { [weak self] in
            withAnimation(.easeInOut(duration: 0.2)) {
                self?.isShowing = false
            }
        }
        hideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: task)
    }
}

// MARK: - Copy Progress Manager

@MainActor
class CopyProgressManager: ObservableObject {
    static let shared = CopyProgressManager()

    @Published var isActive = false
    @Published var currentFile = ""
    @Published var filesCopied = 0

    func start() {
        isActive = true
        currentFile = ""
        filesCopied = 0
    }

    func update(file: String, count: Int) {
        currentFile = file
        filesCopied = count
    }

    func finish() {
        isActive = false
    }

    /// Run a filtered copy of selection items in background with progress updates.
    /// Returns the number of top-level items successfully copied.
    func copyItems(_ items: [(name: String, url: URL)], to destination: URL) async -> Int {
        let skipFolders = Set(AppSettings.shared.copySkipFolders)
        let itemsCopy = items

        await MainActor.run { start() }

        let count = await Task.detached { [skipFolders, itemsCopy] () -> Int in
            let fm = FileManager.default
            var copied = 0
            var fileCount = 0
            var lastUpdate = Date.distantPast

            for (name, url) in itemsCopy {
                // Compute unique destination
                var destURL = destination.appendingPathComponent(name)
                if fm.fileExists(atPath: destURL.path) {
                    let baseName = (name as NSString).deletingPathExtension
                    let ext = (name as NSString).pathExtension
                    var counter = 2
                    repeat {
                        let newName = ext.isEmpty ? "\(baseName) \(counter)" : "\(baseName) \(counter).\(ext)"
                        destURL = destination.appendingPathComponent(newName)
                        counter += 1
                    } while fm.fileExists(atPath: destURL.path)
                }

                do {
                    try copyItemFiltered(at: url, to: destURL, skipping: skipFolders) { fileName in
                        fileCount += 1
                        let now = Date()
                        if now.timeIntervalSince(lastUpdate) >= 0.1 {
                            lastUpdate = now
                            let c = fileCount
                            let f = fileName
                            Task { @MainActor in
                                Self.shared.update(file: f, count: c)
                            }
                        }
                    }
                    copied += 1
                } catch {
                    let errorMsg = error.localizedDescription
                    Task { @MainActor in
                        ToastManager.shared.showError("Failed to copy \(name): \(errorMsg)")
                    }
                }
            }

            // Final update
            let finalCount = fileCount
            Task { @MainActor in
                Self.shared.update(file: "", count: finalCount)
            }

            return copied
        }.value

        await MainActor.run { finish() }
        return count
    }
}

// MARK: - Toast View

struct ToastView: View {
    @ObservedObject var manager = ToastManager.shared

    var body: some View {
        if manager.isShowing {
            Text(manager.message)
                .textStyle(.buttons)
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(manager.style == .error ? Color.red.opacity(0.85) : Color.black.opacity(0.75))
                .cornerRadius(8)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }
}

// MARK: - Copy Progress View

struct CopyProgressView: View {
    @ObservedObject var progress = CopyProgressManager.shared

    var body: some View {
        if progress.isActive {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 14, height: 14)
                Text("Copying: \(progress.currentFile)")
                    .textStyle(.buttons)
                    .lineLimit(1)
                Text("(\(progress.filesCopied) files)")
                    .textStyle(.small)
                    .foregroundColor(.secondary)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.75))
            .cornerRadius(8)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }
}

// MARK: - iPhone Transfer Progress Manager

@MainActor
class iPhoneTransferProgressManager: ObservableObject {
    static let shared = iPhoneTransferProgressManager()

    @Published var isActive = false
    @Published var currentFile = ""
    @Published var filesCompleted = 0
    @Published var totalFiles = 0
    @Published var direction: TransferDirection = .upload

    enum TransferDirection {
        case upload
        case download
    }

    func start(direction: TransferDirection, total: Int) {
        self.direction = direction
        self.totalFiles = total
        self.filesCompleted = 0
        self.currentFile = ""
        self.isActive = true
    }

    func update(file: String, completed: Int) {
        currentFile = file
        filesCompleted = completed
    }

    func finish() {
        isActive = false
    }
}

// MARK: - iPhone Transfer Progress View

struct iPhoneTransferProgressView: View {
    @ObservedObject var progress = iPhoneTransferProgressManager.shared

    var body: some View {
        if progress.isActive {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 14, height: 14)
                Image(systemName: progress.direction == .upload ? "arrow.up.doc" : "arrow.down.doc")
                    .textStyle(.buttons)
                Text(progress.direction == .upload ? "Uploading:" : "Downloading:")
                    .textStyle(.buttons)
                Text(progress.currentFile)
                    .textStyle(.buttons)
                    .lineLimit(1)
                Text("(\(progress.filesCompleted)/\(progress.totalFiles))")
                    .textStyle(.small)
                    .foregroundColor(.secondary)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.pink.opacity(0.85))
            .cornerRadius(8)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }
}
