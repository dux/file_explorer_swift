import SwiftUI
import AppKit

enum PreviewType {
    case text
    case json
    case markdown
    case image
    case pdf
    case makefile
    case archive
    case comic
    case epub
    case audio
    case video
    case dmg
    case none

    static func detect(for url: URL) -> PreviewType {
        let ext = url.pathExtension.lowercased()
        let filename = url.lastPathComponent.lowercased()

        // Check by extension first
        if ["md", "markdown"].contains(ext) {
            return .markdown
        }

        if ext == "json" {
            return .json
        }

        if ["jpg", "jpeg", "png", "gif", "bmp", "webp", "heic", "tiff", "ico", "svg", "avif"].contains(ext) {
            return .image
        }

        if ext == "pdf" {
            return .pdf
        }

        if ["cbz", "cbr"].contains(ext) {
            return .comic
        }

        if ext == "epub" {
            return .epub
        }

        if ["zip", "tar", "tgz", "gz", "bz2", "xz", "rar", "7z"].contains(ext) {
            return .archive
        }

        if ["dmg", "iso", "sparseimage", "sparsebundle"].contains(ext) {
            return .dmg
        }

        // Audio files
        if ["mp3", "m4a", "wav", "aac", "flac", "ogg", "wma", "aiff", "aif", "alac", "opus"].contains(ext) {
            return .audio
        }

        // Video files
        if ["mp4", "mov", "m4v", "avi", "mkv", "webm", "wmv", "flv", "ogv", "3gp"].contains(ext) {
            return .video
        }

        // Known text extensions
        let textExtensions = Set([
            "txt", "yaml", "yml", "toml", "xml", "csv", "log",
            "sh", "bash", "zsh", "fish",
            "py", "js", "ts", "jsx", "tsx", "swift", "rb", "go", "rs",
            "c", "cpp", "h", "hpp", "m", "mm", "java", "kt", "scala",
            "css", "scss", "sass", "less", "html", "htm",
            "sql", "graphql", "proto",
            "env", "ini", "conf", "config", "cfg",
            "gitignore", "gitattributes", "dockerignore",
            "editorconfig", "prettierrc", "eslintrc",
            "lock", "sum"
        ])

        if textExtensions.contains(ext) {
            return .text
        }

        // Makefile detection
        if filename == "makefile" || filename == "gnumakefile" || ext == "mk" || filename.hasSuffix(".makefile") {
            return .makefile
        }

        // Known text filenames (no extension)
        let textFilenames = Set([
            "procfile", "rakefile", "gemfile", "podfile", "cartfile",
            "dockerfile", "vagrantfile", "brewfile",
            "readme", "license", "changelog", "authors", "contributors",
            "todo", "notes", "copying", "install", "version"
        ])

        if textFilenames.contains(filename) || textFilenames.contains(filename.replacingOccurrences(of: ".", with: "")) {
            return .text
        }

        // Try to detect if file is text by reading first bytes
        if isTextFile(url) {
            return .text
        }

        return .none
    }

    private static func isTextFile(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }

        guard let data = try? handle.read(upToCount: 8192) else { return false }

        // Check for null bytes (binary indicator)
        if data.contains(0) {
            return false
        }

        // Check if mostly printable ASCII or valid UTF-8
        let validCount = data.filter { byte in
            (byte >= 32 && byte < 127) || byte == 9 || byte == 10 || byte == 13
        }.count

        return Double(validCount) / Double(data.count) > 0.85
    }
}

struct PreviewPane: View {
    let url: URL
    var manager: FileExplorerManager?

    var body: some View {
        let previewType = PreviewType.detect(for: url)

        switch previewType {
        case .markdown:
            MarkdownPreviewView(url: url)
        case .json:
            JSONPreviewView(url: url)
        case .image:
            ImagePreviewView(url: url)
        case .pdf:
            PDFPreviewView(url: url)
        case .makefile:
            MakefilePreviewView(url: url)
        case .archive:
            if let manager = manager {
                ArchivePreviewView(url: url, manager: manager)
            } else {
                ArchivePreviewView(url: url, manager: FileExplorerManager())
            }
        case .comic:
            ComicPreviewView(url: url)
        case .epub:
            EpubPreviewView(url: url)
        case .audio:
            AudioPreviewView(url: url)
        case .video:
            VideoPreviewView(url: url)
        case .dmg:
            DMGPreviewView(url: url)
        case .text:
            TextPreviewView(url: url)
        case .none:
            NoPreviewView(url: url)
        }
    }
}

struct NoPreviewView: View {
    let url: URL

    var body: some View {
        VStack(spacing: 0) {
            PreviewHeader(title: "No preview", icon: "doc.fill", color: .secondary)
            Divider()

            VStack(spacing: 12) {
                Image(systemName: "eye.slash")
                    .font(.system(size: 32))
                    .foregroundColor(.secondary)
                Text("No preview available")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct PreviewHeader: View {
    let title: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color)
                .frame(width: 22)

            Text(title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
