import SwiftUI
import WebKit

struct ComicPreviewView: View {
    let url: URL
    @State private var htmlPath: URL? = nil
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            PreviewHeader(title: url.lastPathComponent, icon: "book.fill", color: .purple)
            Divider()

            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Extracting preview...")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let htmlPath = htmlPath {
                ComicWebView(fileURL: htmlPath)
            }
        }
        .onAppear { extractImages() }
        .onChange(of: url) { _ in extractImages() }
    }

    private func extractImages() {
        isLoading = true
        let archiveURL = url

        Task.detached(priority: .userInitiated) {
            let path = ComicExtractor.extractAndGenerateHTML(from: archiveURL)

            await MainActor.run {
                htmlPath = path
                isLoading = false
            }
        }
    }
}

// Separate class to avoid View actor isolation
enum ComicExtractor {
    static func extractAndGenerateHTML(from url: URL) -> URL? {
        let ext = url.pathExtension.lowercased()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ComicPreview")
            .appendingPathComponent(UUID().uuidString)

        // Create temp dir
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        // Extract files
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
            return nil
        }

        // Find image files
        let imageExtensions = Set(["jpg", "jpeg", "png", "gif", "webp", "bmp"])
        var imageURLs: [URL] = []

        if let contents = try? FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil) {
            imageURLs = contents.filter { fileURL in
                imageExtensions.contains(fileURL.pathExtension.lowercased())
            }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        }

        // Take first 6
        let previewImages = Array(imageURLs.prefix(9))

        if previewImages.isEmpty {
            return nil
        }

        // Generate HTML and save to file
        let html = generateHTML(images: previewImages, total: imageURLs.count)
        let htmlFile = tempDir.appendingPathComponent("preview.html")

        do {
            try html.write(to: htmlFile, atomically: true, encoding: .utf8)
            return htmlFile
        } catch {
            return nil
        }
    }

    private static func generateHTML(images: [URL], total: Int) -> String {
        let imagesTags = images.enumerated().map { index, url in
            let filename = url.lastPathComponent
            return "<img src=\"\(filename)\" alt=\"Page \(index + 1)\">"
        }.joined(separator: "\n")

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <style>
                :root { color-scheme: light dark; }
                * { margin: 0; padding: 0; box-sizing: border-box; }
                body {
                    font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                    background: transparent;
                    padding: 12px;
                }
                .info {
                    padding: 8px;
                    margin-bottom: 12px;
                    font-size: 12px;
                    color: #666;
                }
                @media (prefers-color-scheme: dark) {
                    .info { color: #999; }
                }
                .images {
                    display: flex;
                    flex-wrap: wrap;
                    gap: 16px;
                    padding-bottom: 24px;
                }
                .images img {
                    max-width: 600px;
                    max-height: 600px;
                    height: auto;
                    border-radius: 4px;
                    box-shadow: 0 2px 8px rgba(0,0,0,0.2);
                    margin-right: 8px;
                    margin-bottom: 8px;
                }
            </style>
        </head>
        <body>
            <div class="info">Showing \(images.count) of \(total) pages</div>
            <div class="images">
                \(imagesTags)
            </div>
        </body>
        </html>
        """
    }
}

struct ComicWebView: NSViewRepresentable {
    let fileURL: URL

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())
    }
}
