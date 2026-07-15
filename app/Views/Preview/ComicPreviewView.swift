import SwiftUI
import AppKit

struct ComicPreviewView: View {
    let url: URL
    @State private var pages: [URL] = []
    @State private var totalPages: Int = 0
    @State private var isLoading = true
    @State private var error: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            PreviewHeader(title: "Comic preview", icon: "book.fill", color: .purple)
            Divider()

            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Extracting pages...")
                        .textStyle(.buttons)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .textStyle(.title)
                        .foregroundColor(.secondary)
                    Text(error)
                        .textStyle(.buttons)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Static two-up spread page, rendered in a web view: no SwiftUI relayout on resize.
                HTMLPreviewView(bodyHTML: pagesHTML, extraCSS: Self.css)
            }
        }
        .task(id: url) {
            await extractPages()
        }
    }

    private static let css = """
    body { padding: 0; }
    .count { color: #888; text-align: center; font-size: 12px; padding: 6px 0; }
    .pages { display: grid; grid-template-columns: 1fr 1fr; gap: 2px; }
    .pages img { width: 100%; height: auto; display: block; }
    """

    private var pagesHTML: String {
        let imgs = pages
            .map { "<img src=\"\(HTMLPreviewView.fileSrc(for: $0))\">" }
            .joined()
        let count = totalPages > 0 ? "<div class=\"count\">\(totalPages) pages</div>" : ""
        return count + "<div class=\"pages\">\(imgs)</div>"
    }

    private func extractPages() async {
        isLoading = true
        error = nil
        pages = []

        let archiveURL = url
        let result = await Task.detached(priority: .userInitiated) {
            ComicExtractor.extract(from: archiveURL)
        }.value

        switch result {
        case .success(let (urls, total)):
            pages = urls
            totalPages = total
        case .failure(let err):
            error = err.localizedDescription
        }
        isLoading = false
    }
}

enum ComicExtractor {
    private static let imageExtensions = FileExtensions.comicImages

    static func extract(from url: URL) -> Result<([URL], Int), Error> {
        let ext = url.pathExtension.lowercased()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ComicPreview")
            .appendingPathComponent(UUID().uuidString)

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            return .failure(error)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.currentDirectoryURL = tempDir

        if ext == "cbr" {
            process.arguments = ["unrar", "e", "-o+", url.path]
        } else {
            process.arguments = ["unzip", "-j", "-o", url.path]
        }

        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return .failure(error)
        }

        guard let contents = try? FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil) else {
            return .success(([], 0))
        }

        let imageURLs = contents.filter {
            imageExtensions.contains($0.pathExtension.lowercased())
        }.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }

        return .success((imageURLs, imageURLs.count))
    }
}
