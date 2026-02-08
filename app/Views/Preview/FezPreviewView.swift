import SwiftUI
import WebKit

struct FezPreviewView: View {
    let url: URL
    @ObservedObject private var settings = AppSettings.shared
    @State private var content: String = ""
    @State private var showSource = false
    @State private var infoItems: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                PreviewHeader(title: "Fez component", icon: "puzzlepiece.fill", color: .orange)

                Spacer()

                Picker("", selection: $showSource) {
                    Text("Preview").tag(false)
                    Text("Source").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
                .padding(.trailing, 8)

                if showSource {
                    FontSizeControls(settings: settings)
                }
            }
            Divider()

            if !infoItems.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(infoItems, id: \.self) { item in
                        HStack(alignment: .top, spacing: 6) {
                            Text("\u{2022}")
                                .foregroundColor(.secondary)
                            Text(item)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor))
                Divider()
            }

            if showSource {
                SyntaxHighlightView(code: content, language: "html", fontSize: settings.previewFontSize)
            } else {
                FezLivePreviewWebView(source: content, fileURL: url)
            }
        }
        .onAppear { loadContent() }
        .onChange(of: url) { _ in loadContent() }
    }

    private func loadContent() {
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            content = String(text.prefix(200_000))
            infoItems = extractInfo(from: text)
        } else {
            content = "Unable to load file"
            infoItems = []
        }
    }

    private func extractInfo(from source: String) -> [String] {
        guard let infoStart = source.range(of: "<info>"),
              let infoEnd = source.range(of: "</info>") else {
            return []
        }
        let infoBlock = String(source[infoStart.upperBound..<infoEnd.lowerBound])
        // Extract text from <li> tags
        var items: [String] = []
        var remaining = infoBlock[...]
        while let liStart = remaining.range(of: "<li>"),
              let liEnd = remaining.range(of: "</li>") {
            let raw = String(remaining[liStart.upperBound..<liEnd.lowerBound])
            // Strip inline HTML tags like <code>
            let clean = raw.replacingOccurrences(
                of: "<[^>]+>",
                with: "",
                options: .regularExpression
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty {
                items.append(clean)
            }
            remaining = remaining[liEnd.upperBound...]
        }
        return items
    }
}

struct FezLivePreviewWebView: NSViewRepresentable {
    let source: String
    let fileURL: URL

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        loadPreview(webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        loadPreview(webView)
    }

    private func loadPreview(_ webView: WKWebView) {
        guard !source.isEmpty else {
            webView.loadHTMLString("<p style='color:gray;padding:16px'>No content</p>", baseURL: nil)
            return
        }

        let componentName = fileURL.deletingPathExtension().lastPathComponent.lowercased()
        let fezFilePath = fileURL.path

        // Extract demo tag content if present
        let demoContent: String
        if let demoStart = source.range(of: "<demo>"),
           let demoEnd = source.range(of: "</demo>") {
            demoContent = String(source[demoStart.upperBound..<demoEnd.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            demoContent = "<\(componentName)></\(componentName)>"
        }

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <link rel="stylesheet" href="https://cdn.simplecss.org/simple.css" />
            <script src="https://dux.github.io/fez/dist/fez.js"></script>
            <script fez="\(fezFilePath)"></script>
            <style>
                :root { color-scheme: light dark; }
                body {
                    font-size: 14px;
                    padding: 16px;
                    background: transparent;
                    max-width: unset;
                }
                #error {
                    color: #cf222e;
                    font-family: ui-monospace, monospace;
                    font-size: 12px;
                    padding: 8px;
                    white-space: pre-wrap;
                    display: none;
                }
                @media (prefers-color-scheme: dark) {
                    #error { color: #ff7b72; }
                }
            </style>
        </head>
        <body>
            <div id="error"></div>
            \(demoContent)
            <script>
                window.onerror = function(msg, url, line) {
                    var el = document.getElementById('error');
                    el.style.display = 'block';
                    el.textContent = 'Error: ' + msg + (line ? ' (line ' + line + ')' : '');
                };
            </script>
        </body>
        </html>
        """

        // Write temp HTML to app cache dir, grant read access to root so Fez can fetch the .fez file
        let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent("fez-preview")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let tmpHTML = cacheDir.appendingPathComponent("preview.html")
        do {
            try html.write(to: tmpHTML, atomically: true, encoding: .utf8)
            webView.loadFileURL(tmpHTML, allowingReadAccessTo: URL(fileURLWithPath: "/"))
        } catch {
            webView.loadHTMLString("<p style='color:red;padding:16px'>Failed to create preview</p>", baseURL: nil)
        }
    }
}
