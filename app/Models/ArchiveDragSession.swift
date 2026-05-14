import Foundation

@MainActor
final class ArchiveDragSession {
    static let shared = ArchiveDragSession()

    struct Pending: Sendable {
        let archive: URL
        let entryPath: String
        let entryName: String
        let isDirectory: Bool
        let archiveExt: String
    }

    var pending: Pending?

    private init() {}

    func beginDrag(pending p: Pending, onComplete: @escaping @MainActor () -> Void) -> URL {
        pending = p

        guard !p.isDirectory, p.archiveExt == "zip" else {
            return URL(fileURLWithPath: "/tmp/.archive-drag-marker")
        }

        let destination = p.archive.deletingLastPathComponent()
        switch Self.extractSynchronously(pending: p, destination: destination, stripPath: true) {
        case .ok(let extractedURL):
            pending = nil
            ToastManager.shared.show("Extracted \(p.entryName)")
            onComplete()
            return extractedURL
        case .unsupported:
            ToastManager.shared.showError("Unsupported archive format")
        case .failed(let message):
            ToastManager.shared.showError(message)
        }
        return URL(fileURLWithPath: "/tmp/.archive-drag-marker")
    }

    /// If a drag from an archive entry is in flight, extract it into `destination`
    /// using the matching CLI tool and refresh on completion. Returns true if it handled
    /// the drop so the caller can skip normal URL handling.
    func handleDrop(to destination: URL, onComplete: @escaping @MainActor () -> Void) -> Bool {
        guard let p = pending else { return false }
        pending = nil

        ToastManager.shared.show("Extracting \(p.entryName)...")

        Task { @MainActor in
            let result = await Self.extract(pending: p, destination: destination)
            switch result {
            case .ok:
                ToastManager.shared.show("Extracted \(p.entryName)")
                onComplete()
            case .unsupported:
                ToastManager.shared.showError("Unsupported archive format")
            case .failed(let message):
                ToastManager.shared.showError(message)
            }
        }
        return true
    }

    enum ExtractResult: Sendable {
        case ok(URL)
        case unsupported
        case failed(String)
    }

    nonisolated static func extract(pending p: Pending, destination: URL, stripPath: Bool = false) async -> ExtractResult {
        await Task.detached(priority: .userInitiated) { () -> ExtractResult in
            extractSynchronously(pending: p, destination: destination, stripPath: stripPath)
        }.value
    }

    nonisolated static func extractSynchronously(pending p: Pending, destination: URL, stripPath: Bool = false) -> ExtractResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        let outputURL = destination.appendingPathComponent(stripPath && !p.isDirectory ? p.entryName : p.entryPath)
        switch p.archiveExt {
        case "zip":
            var arguments = ["unzip", "-o"]
            if stripPath && !p.isDirectory {
                arguments.append("-j")
            }
            arguments.append(contentsOf: [p.archive.path, p.entryPath, "-d", destination.path])
            process.arguments = arguments
        case "tar", "tgz", "gz", "bz2", "xz":
            process.arguments = ["tar", "-xf", p.archive.path, "-C", destination.path, p.entryPath]
        default:
            return .unsupported
        }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            _ = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                return .ok(outputURL)
            }
            return .failed("Failed to extract \(p.entryName)")
        } catch {
            return .failed("Extract error: \(error.localizedDescription)")
        }
    }
}
