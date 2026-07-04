import SwiftUI
import WebKit
import AppKit

/// Shared WKWebView renderer for static HTML previews.
///
/// Wraps a body fragment in a standard page (system font, dark-mode aware, transparent
/// background), opens link clicks in the system browser, and serves local files on demand
/// through the `previewfile://` scheme so images don't have to be base64-inlined.
/// Because the page is static, pane resizes reflow inside WebKit with no SwiftUI relayout.
struct HTMLPreviewView: NSViewRepresentable {
    let bodyHTML: String
    var extraCSS: String = ""

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(LocalFileSchemeHandler(), forURLScheme: LocalFileSchemeHandler.scheme)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator

        let html = Self.page(body: bodyHTML, extraCSS: extraCSS)
        context.coordinator.loadedHTML = html
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Static page: only reload when the content actually changes (e.g. async data arrives),
        // never on a plain resize.
        let html = Self.page(body: bodyHTML, extraCSS: extraCSS)
        guard context.coordinator.loadedHTML != html else { return }
        context.coordinator.loadedHTML = html
        webView.loadHTMLString(html, baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedHTML: String?

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }

    // MARK: - Helpers

    /// A `previewfile://` src that the scheme handler resolves to the given local file.
    static func fileSrc(for url: URL) -> String {
        LocalFileSchemeHandler.src(for: url)
    }

    /// Escapes a string for safe inclusion in HTML text or attributes.
    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func page(body: String, extraCSS: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        \(baseCSS)
        \(extraCSS)
        </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    private static let baseCSS = """
    :root { color-scheme: light dark; }
    * { box-sizing: border-box; }
    body {
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
        margin: 0;
        padding: 14px;
        background: transparent;
        color: #24292f;
        font-size: 13px;
        line-height: 1.5;
    }
    a { color: #2563eb; text-decoration: none; }
    @media (prefers-color-scheme: dark) {
        body { color: #e6e6e6; }
        a { color: #58a6ff; }
    }
    """
}

/// Serves local files to a WKWebView through a custom scheme, avoiding base64 inlining and
/// the file-access restrictions that block `file://` resources from string-loaded pages.
final class LocalFileSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "previewfile"

    /// Builds a `previewfile://f/<base64url-of-path>` URL for a local file.
    static func src(for url: URL) -> String {
        let encoded = Data(url.path.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "\(scheme)://f/\(encoded)"
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              let path = Self.decodePath(from: url) else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        let fileURL = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: fileURL) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        let response = URLResponse(
            url: url,
            mimeType: Self.mimeType(for: fileURL.pathExtension.lowercased()),
            expectedContentLength: data.count,
            textEncodingName: nil
        )
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private static func decodePath(from url: URL) -> String? {
        var b64 = url.lastPathComponent
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while !b64.count.isMultiple(of: 4) { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let path = String(data: data, encoding: .utf8) else { return nil }
        return path
    }

    private static func mimeType(for ext: String) -> String {
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "bmp": return "image/bmp"
        case "tiff", "tif": return "image/tiff"
        case "heic", "heif": return "image/heic"
        case "svg": return "image/svg+xml"
        case "avif": return "image/avif"
        default: return "application/octet-stream"
        }
    }
}
