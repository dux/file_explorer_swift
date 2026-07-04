import SwiftUI
import WebKit

struct MarkdownPreviewView: View {
    let url: URL
    @ObservedObject private var settings = AppSettings.shared
    @State private var markdown: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                PreviewHeader(title: "Markdown preview", icon: "doc.richtext.fill", color: .purple)

                Spacer()

                FontSizeControls(settings: settings)
            }
            Divider()
            MarkdownWebView(markdown: markdown, fontSize: settings.previewFontSize)
        }
        .task(id: url) {
            markdown = await readFileText(url) ?? "Unable to load file"
        }
    }
}

struct MarkdownWebView: NSViewRepresentable {
    let markdown: String
    let fontSize: CGFloat

    // marked.js is bundled locally and inlined into the page, so previews render offline.
    private static let markedJS: String = {
        guard let jsURL = Bundle.module.url(forResource: "marked.min", withExtension: "js"),
              let js = try? String(contentsOf: jsURL, encoding: .utf8) else { return "" }
        return js
    }()

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.setValue(false, forKey: "drawsBackground")
        render(webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        render(webView)
    }

    private func render(_ webView: WKWebView) {
        let escapedMarkdown = markdown
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <script>\(Self.markedJS)</script>
            <style>
                :root { color-scheme: light dark; }
                body {
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
                    font-size: \(Int(fontSize))px;
                    line-height: 1.6;
                    padding: 16px;
                    margin: 0;
                    background: transparent;
                    color: #24292f;
                }
                @media (prefers-color-scheme: dark) {
                    body { color: #c9d1d9; }
                    a { color: #58a6ff; }
                    code { background: #343941; }
                    pre { background: #282c34; }
                }
                code {
                    background: #f6f8fa;
                    padding: 0.2em 0.4em;
                    border-radius: 4px;
                    font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, monospace;
                    font-size: 0.9em;
                }
                pre {
                    background: #f6f8fa;
                    padding: 12px;
                    border-radius: 6px;
                    overflow-x: auto;
                }
                pre code { background: none; padding: 0; }
                h1 { font-size: 1.8em; }
                h2 { font-size: 1.5em; }
                h3 { font-size: 1.25em; }
                table {
                    border-collapse: collapse;
                    margin: 1em 0;
                }
                th, td {
                    border: 1px solid #d0d7de;
                    padding: 8px 12px;
                    text-align: left;
                }
                th {
                    background: #f6f8fa;
                    font-weight: 600;
                }
                tr:nth-child(even) {
                    background: #f6f8fa;
                }
                @media (prefers-color-scheme: dark) {
                    th, td { border-color: #30363d; }
                    th { background: #21262d; }
                    tr:nth-child(even) { background: #161b22; }
                }
            </style>
        </head>
        <body>
            <div id="content"></div>
            <script>
                const markdown = `\(escapedMarkdown)`;
                document.getElementById('content').innerHTML = marked.parse(markdown);
            </script>
        </body>
        </html>
        """

        webView.loadHTMLString(html, baseURL: nil)
    }
}
