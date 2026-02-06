import SwiftUI
import WebKit

struct EpubPreviewView: View {
    let url: URL
    @State private var htmlPath: URL? = nil
    @State private var isLoading = true
    @State private var errorMessage: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            PreviewHeader(title: "EPUB preview", icon: "book.fill", color: .orange)
            Divider()

            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Extracting preview...")
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
            } else if let htmlPath = htmlPath {
                EpubWebView(fileURL: htmlPath)
            }
        }
        .onAppear { extractEpub() }
        .onChange(of: url) { _ in extractEpub() }
    }

    private func extractEpub() {
        isLoading = true
        errorMessage = nil
        let epubURL = url

        Task.detached(priority: .userInitiated) {
            let result = EpubExtractor.extractAndGenerateHTML(from: epubURL)

            await MainActor.run {
                switch result {
                case .success(let path):
                    htmlPath = path
                case .failure(let error):
                    errorMessage = error.message
                }
                isLoading = false
            }
        }
    }
}

struct EpubError: Error {
    let message: String
}

enum EpubExtractor {
    static func extractAndGenerateHTML(from url: URL) -> Result<URL, EpubError> {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("EpubPreview")
            .appendingPathComponent(UUID().uuidString)

        // Create temp dir
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            return .failure(EpubError(message: "Failed to create temp dir"))
        }

        // Extract epub (it's a zip)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["unzip", "-o", url.path, "-d", tempDir.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return .failure(EpubError(message: "Failed to extract epub"))
        }

        // Parse container.xml to find content.opf
        let containerPath = tempDir.appendingPathComponent("META-INF/container.xml")
        guard let containerData = try? String(contentsOf: containerPath, encoding: .utf8) else {
            return .failure(EpubError(message: "Invalid epub: no container.xml"))
        }

        // Extract rootfile path from container.xml
        guard let opfPath = extractOPFPath(from: containerData) else {
            return .failure(EpubError(message: "Invalid epub: no content.opf reference"))
        }

        let opfURL = tempDir.appendingPathComponent(opfPath)
        let opfDir = opfURL.deletingLastPathComponent()

        guard let opfData = try? String(contentsOf: opfURL, encoding: .utf8) else {
            return .failure(EpubError(message: "Invalid epub: cannot read content.opf"))
        }

        // Extract spine items (chapter files in order)
        let spineItems = extractSpineItems(from: opfData, baseDir: opfDir)

        if spineItems.isEmpty {
            return .failure(EpubError(message: "No content found in epub"))
        }

        // Read first few chapters and combine
        let maxChapters = 3
        var combinedContent = ""

        for (index, itemURL) in spineItems.prefix(maxChapters).enumerated() {
            if let content = try? String(contentsOf: itemURL, encoding: .utf8) {
                // Extract body content
                if let bodyContent = extractBodyContent(from: content) {
                    combinedContent += "<div class=\"chapter\">\(bodyContent)</div>\n"
                }
            }

            if index >= maxChapters - 1 { break }
        }

        if combinedContent.isEmpty {
            return .failure(EpubError(message: "Could not extract content from epub"))
        }

        // Generate preview HTML
        let html = generateHTML(content: combinedContent, title: url.lastPathComponent, totalChapters: spineItems.count)
        let htmlFile = tempDir.appendingPathComponent("preview.html")

        do {
            try html.write(to: htmlFile, atomically: true, encoding: .utf8)
            return .success(htmlFile)
        } catch {
            return .failure(EpubError(message: "Failed to create preview"))
        }
    }

    private static func extractOPFPath(from container: String) -> String? {
        // Look for full-path attribute in rootfile element
        let pattern = #"full-path\s*=\s*["']([^"']+)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: container, range: NSRange(container.startIndex..., in: container)),
              let range = Range(match.range(at: 1), in: container) else {
            return nil
        }
        return String(container[range])
    }

    private static func extractSpineItems(from opf: String, baseDir: URL) -> [URL] {
        var items: [URL] = []

        // First build manifest map (id -> href)
        var manifest: [String: String] = [:]
        let manifestPattern = #"<item[^>]+id\s*=\s*["']([^"']+)["'][^>]+href\s*=\s*["']([^"']+)["']"#
        let manifestPattern2 = #"<item[^>]+href\s*=\s*["']([^"']+)["'][^>]+id\s*=\s*["']([^"']+)["']"#

        if let regex = try? NSRegularExpression(pattern: manifestPattern) {
            let matches = regex.matches(in: opf, range: NSRange(opf.startIndex..., in: opf))
            for match in matches {
                if let idRange = Range(match.range(at: 1), in: opf),
                   let hrefRange = Range(match.range(at: 2), in: opf) {
                    manifest[String(opf[idRange])] = String(opf[hrefRange])
                }
            }
        }

        if let regex = try? NSRegularExpression(pattern: manifestPattern2) {
            let matches = regex.matches(in: opf, range: NSRange(opf.startIndex..., in: opf))
            for match in matches {
                if let hrefRange = Range(match.range(at: 1), in: opf),
                   let idRange = Range(match.range(at: 2), in: opf) {
                    manifest[String(opf[idRange])] = String(opf[hrefRange])
                }
            }
        }

        // Extract spine order
        let spinePattern = #"<itemref[^>]+idref\s*=\s*["']([^"']+)["']"#
        if let regex = try? NSRegularExpression(pattern: spinePattern) {
            let matches = regex.matches(in: opf, range: NSRange(opf.startIndex..., in: opf))
            for match in matches {
                if let range = Range(match.range(at: 1), in: opf) {
                    let idref = String(opf[range])
                    if let href = manifest[idref] {
                        let decodedHref = href.removingPercentEncoding ?? href
                        items.append(baseDir.appendingPathComponent(decodedHref))
                    }
                }
            }
        }

        return items
    }

    private static func extractBodyContent(from html: String) -> String? {
        // Simple extraction of body content
        let bodyPattern = #"<body[^>]*>([\s\S]*?)</body>"#
        if let regex = try? NSRegularExpression(pattern: bodyPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) {
            return String(html[range])
        }
        return nil
    }

    private static func generateHTML(content: String, title: String, totalChapters: Int) -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <style>
                :root { color-scheme: light dark; }
                * { margin: 0; padding: 0; box-sizing: border-box; }
                body {
                    font-family: Georgia, "Times New Roman", serif;
                    font-size: 14px;
                    line-height: 1.7;
                    background: transparent;
                    padding: 16px 24px;
                    color: #333;
                }
                @media (prefers-color-scheme: dark) {
                    body { color: #ccc; }
                }
                .info {
                    padding: 8px 0;
                    margin-bottom: 16px;
                    font-size: 12px;
                    color: #666;
                    font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                    border-bottom: 1px solid #ddd;
                }
                @media (prefers-color-scheme: dark) {
                    .info { color: #999; border-color: #444; }
                }
                .chapter {
                    margin-bottom: 24px;
                }
                h1, h2, h3 { margin: 1em 0 0.5em; font-family: -apple-system, BlinkMacSystemFont, sans-serif; }
                h1 { font-size: 1.5em; }
                h2 { font-size: 1.3em; }
                h3 { font-size: 1.1em; }
                p { margin: 0.8em 0; text-align: justify; }
                img { max-width: 100%; height: auto; }
            </style>
        </head>
        <body>
            <div class="info">Preview of \(totalChapters) chapters</div>
            \(content)
        </body>
        </html>
        """
    }
}

struct EpubWebView: NSViewRepresentable {
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
