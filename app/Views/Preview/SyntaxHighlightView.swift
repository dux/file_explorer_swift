import SwiftUI
import WebKit

struct SyntaxHighlightView: NSViewRepresentable {
    let code: String
    let language: String
    let fontSize: CGFloat

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        loadContent(webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        loadContent(webView)
    }

    private func loadContent(_ webView: WKWebView) {
        let escapedCode = code
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>
            <style>
                :root { color-scheme: light dark; }
                * {
                    margin: 0;
                    padding: 0;
                    box-sizing: border-box;
                }
                body {
                    background: transparent;
                    font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Monaco, Consolas, monospace;
                    font-size: \(Int(fontSize))px;
                    line-height: 1.5;
                    padding: 12px;
                    color: #1f2328;
                }
                pre {
                    margin: 0;
                    white-space: pre;
                    overflow: visible;
                }
                code, .hljs {
                    font-family: inherit;
                    font-size: inherit;
                    background: transparent !important;
                    padding: 0 !important;
                }

                /* Light mode (default) */
                .hljs-keyword, .hljs-selector-tag, .hljs-built_in, .hljs-name { color: #cf222e; }
                .hljs-string, .hljs-addition { color: #0a3069; }
                .hljs-number, .hljs-literal { color: #0550ae; }
                .hljs-function, .hljs-title, .hljs-title.function_ { color: #8250df; }
                .hljs-comment, .hljs-quote { color: #6e7781; font-style: italic; }
                .hljs-variable, .hljs-template-variable, .hljs-attribute { color: #953800; }
                .hljs-attr, .hljs-property { color: #0550ae; }
                .hljs-section, .hljs-selector-class { color: #0550ae; font-weight: bold; }
                .hljs-meta, .hljs-doctag { color: #6e7781; }
                .hljs-type, .hljs-class { color: #953800; }
                .hljs-symbol, .hljs-bullet { color: #0550ae; }
                .hljs-deletion { color: #82071e; background: #ffebe9; }
                .hljs-regexp, .hljs-link { color: #0a3069; }

                /* Dark mode */
                @media (prefers-color-scheme: dark) {
                    body { color: #e6edf3; }
                    .hljs-keyword, .hljs-selector-tag, .hljs-built_in, .hljs-name { color: #ff7b72; }
                    .hljs-string, .hljs-addition { color: #a5d6ff; }
                    .hljs-number, .hljs-literal { color: #79c0ff; }
                    .hljs-function, .hljs-title, .hljs-title.function_ { color: #d2a8ff; }
                    .hljs-comment, .hljs-quote { color: #8b949e; font-style: italic; }
                    .hljs-variable, .hljs-template-variable, .hljs-attribute { color: #ffa657; }
                    .hljs-attr, .hljs-property { color: #79c0ff; }
                    .hljs-section, .hljs-selector-class { color: #79c0ff; font-weight: bold; }
                    .hljs-meta, .hljs-doctag { color: #8b949e; }
                    .hljs-type, .hljs-class { color: #ffa657; }
                    .hljs-symbol, .hljs-bullet { color: #79c0ff; }
                    .hljs-deletion { color: #ffdcd7; background: #67060c; }
                    .hljs-regexp, .hljs-link { color: #a5d6ff; }
                }
            </style>
        </head>
        <body>
            <pre><code class="language-\(language)">\(escapedCode)</code></pre>
            <script>hljs.highlightAll();</script>
        </body>
        </html>
        """

        webView.loadHTMLString(html, baseURL: nil)
    }

    static func languageForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        // Programming languages
        case "swift": return "swift"
        case "py", "pyw": return "python"
        case "js", "mjs", "cjs": return "javascript"
        case "ts", "mts", "cts": return "typescript"
        case "jsx": return "javascript"
        case "tsx": return "typescript"
        case "rb", "rake", "gemspec": return "ruby"
        case "go": return "go"
        case "rs": return "rust"
        case "c", "h": return "c"
        case "cpp", "cc", "cxx", "hpp", "hxx": return "cpp"
        case "m", "mm": return "objectivec"
        case "java": return "java"
        case "kt", "kts": return "kotlin"
        case "scala", "sc": return "scala"
        case "php": return "php"
        case "pl", "pm": return "perl"
        case "lua": return "lua"
        case "r": return "r"
        case "zig": return "zig"

        // Shell
        case "sh", "bash", "zsh", "fish": return "bash"

        // Web
        case "html", "htm": return "html"
        case "css": return "css"
        case "fez": return "html"
        case "scss": return "scss"
        case "sass": return "sass"
        case "less": return "less"

        // Data/Config
        case "json": return "json"
        case "xml", "plist": return "xml"
        case "yaml", "yml": return "yaml"
        case "toml": return "toml"
        case "ini", "conf", "cfg": return "ini"

        // Database
        case "sql": return "sql"
        case "graphql", "gql": return "graphql"

        // Other
        case "md", "markdown": return "markdown"
        case "dockerfile": return "dockerfile"
        case "makefile", "mk": return "makefile"
        case "cmake": return "cmake"
        case "diff", "patch": return "diff"

        default: return "plaintext"
        }
    }

    static func languageForFilename(_ filename: String) -> String {
        let lower = filename.lowercased()
        switch lower {
        case "makefile", "gnumakefile": return "makefile"
        case "dockerfile": return "dockerfile"
        case "gemfile", "rakefile", "podfile", "fastfile", "appfile", "matchfile": return "ruby"
        case "procfile": return "yaml"
        case "vagrantfile": return "ruby"
        case "cmakelists.txt": return "cmake"
        case ".gitignore", ".dockerignore", ".npmignore": return "plaintext"
        case ".env", ".env.local", ".env.development", ".env.production": return "bash"
        case ".bashrc", ".zshrc", ".bash_profile", ".zprofile": return "bash"
        default: return "plaintext"
        }
    }
}
