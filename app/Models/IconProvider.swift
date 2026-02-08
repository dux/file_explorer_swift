import AppKit
import SwiftUI

/// Provides catppuccin-themed SVG icons for known file types,
/// falling back to macOS system icons for unrecognized ones.
@MainActor
final class IconProvider {
    static let shared = IconProvider()

    private var cache: [String: NSImage] = [:]

    private init() {}

    // MARK: - Extension to icon name mapping

    private static let extMap: [String: String] = [
        // Programming
        "swift": "swift",
        "rs": "rust",
        "go": "go",
        "py": "python",
        "pyc": "python",
        "rb": "ruby",
        "js": "javascript",
        "mjs": "javascript",
        "cjs": "javascript",
        "jsx": "javascript-react",
        "ts": "typescript",
        "mts": "typescript",
        "cts": "typescript",
        "tsx": "typescript-react",
        "c": "c",
        "h": "c",
        "cpp": "cpp",
        "cc": "cpp",
        "cxx": "cpp",
        "hpp": "cpp",
        "hxx": "cpp",
        "java": "java",
        "kt": "kotlin",
        "kts": "kotlin",
        "scala": "scala",
        "dart": "dart",
        "lua": "lua",
        "ex": "elixir",
        "exs": "elixir",
        "erl": "erlang",
        "hs": "haskell",
        "lhs": "haskell",
        "ml": "ocaml",
        "mli": "ocaml",
        "nim": "nim",
        "pl": "perl",
        "pm": "perl",
        "php": "php",
        "groovy": "groovy",
        "gradle": "groovy",
        "cs": "lib",
        "fs": "lib",
        "fsx": "lib",
        "r": "lib",
        "vb": "lib",
        "nix": "nix",
        "sh": "bash",
        "bash": "bash",
        "zsh": "bash",
        "fish": "bash",
        "bat": "batch",
        "cmd": "batch",
        "ps1": "powershell",
        "psm1": "powershell",

        // Web / Markup / Style
        "html": "html",
        "htm": "html",
        "css": "css",
        "scss": "sass",
        "sass": "sass",
        "less": "less",
        "svg": "svg",
        "graphql": "graphql",
        "gql": "graphql",
        "vue": "lib",
        "fez": "html",
        "postcss": "postcss",

        // Data / Config
        "json": "json",
        "jsonc": "json",
        "json5": "json",
        "yaml": "yaml",
        "yml": "yaml",
        "toml": "toml",
        "xml": "xml",
        "plist": "xml",
        "csv": "csv",
        "tsv": "csv",
        "ini": "config",
        "cfg": "config",
        "conf": "config",
        "env": "env",
        "properties": "properties",
        "proto": "proto",
        "lock": "lock",
        "tex": "latex",
        "bib": "latex",

        // Documents
        "md": "markdown",
        "mdx": "markdown",
        "txt": "text",
        "rtf": "text",
        "pdf": "pdf",
        "doc": "ms-word",
        "docx": "ms-word",
        "xls": "ms-excel",
        "xlsx": "ms-excel",
        "ppt": "ms-powerpoint",
        "pptx": "ms-powerpoint",
        "org": "text",

        // Images
        "jpg": "image",
        "jpeg": "image",
        "png": "image",
        "gif": "image",
        "bmp": "image",
        "webp": "image",
        "heic": "image",
        "heif": "image",
        "tiff": "image",
        "tif": "image",
        "ico": "image",
        "avif": "image",

        // Audio / Video
        "mp3": "audio",
        "wav": "audio",
        "flac": "audio",
        "aac": "audio",
        "ogg": "audio",
        "wma": "audio",
        "m4a": "audio",
        "mp4": "video",
        "mov": "video",
        "avi": "video",
        "mkv": "video",
        "wmv": "video",
        "flv": "video",
        "webm": "video",
        "m4v": "video",

        // Archives
        "zip": "zip",
        "tar": "zip",
        "gz": "zip",
        "bz2": "zip",
        "xz": "zip",
        "7z": "zip",
        "rar": "zip",
        "tgz": "zip",
        "zst": "zip",
        "dmg": "zip",

        // Fonts
        "ttf": "font",
        "otf": "font",
        "woff": "font",
        "woff2": "font",
        "eot": "font",

        // Database
        "sql": "database",
        "sqlite": "database",
        "db": "database",

        // Binary / Executables
        "exe": "exe",
        "dll": "binary",
        "so": "binary",
        "dylib": "binary",
        "o": "binary",
        "a": "binary",
        "wasm": "binary",

        // Keys / Certs
        "pem": "key",
        "crt": "certificate",
        "cer": "certificate",
        "p12": "key",
        "pfx": "key",
        "pub": "key",

        // Diff / Patch
        "diff": "diff",
        "patch": "diff",

        // Makefile handled by filename
        "cmake": "cmake",

        // Docker
        "dockerignore": "docker",

        // Git
        "gitignore": "git",
        "gitattributes": "git",
        "gitmodules": "git",

        // Log
        "log": "log"
    ]

    // Filename (lowercase) to icon name
    private static let nameMap: [String: String] = [
        "makefile": "makefile",
        "cmakelists.txt": "cmake",
        "dockerfile": "docker",
        "docker-compose.yml": "docker-compose",
        "docker-compose.yaml": "docker-compose",
        "compose.yml": "docker-compose",
        "compose.yaml": "docker-compose",
        ".gitignore": "git",
        ".gitattributes": "git",
        ".gitmodules": "git",
        ".env": "env",
        ".env.local": "env",
        ".env.development": "env",
        ".env.production": "env",
        "package.json": "json",
        "package-lock.json": "npm-lock",
        "yarn.lock": "yarn-lock",
        "pnpm-lock.yaml": "lock",
        "gemfile": "ruby",
        "gemfile.lock": "lock",
        "rakefile": "ruby",
        "cargo.toml": "rust",
        "cargo.lock": "lock",
        "go.mod": "go-mod",
        "go.sum": "lock",
        "license": "license",
        "license.md": "license",
        "license.txt": "license",
        "licence": "license",
        "copying": "license",
        "readme": "readme",
        "readme.md": "readme",
        "readme.txt": "readme",
        "changelog": "todo",
        "changelog.md": "todo",
        "todo": "todo",
        "todo.md": "todo",
        ".eslintrc": "config",
        ".eslintrc.json": "config",
        ".prettierrc": "config",
        ".editorconfig": "config",
        "tsconfig.json": "config",
        "tailwind.config.js": "tailwind",
        "tailwind.config.ts": "tailwind",
        "postcss.config.js": "postcss",
        "postcss.config.mjs": "postcss",
        "vite.config.ts": "config",
        "vite.config.js": "config",
        "prisma": "prisma"
    ]

    // MARK: - Public API

    /// Returns an NSImage for the given file URL.
    /// Uses catppuccin icon if available, else macOS system icon.
    /// When `selected` is true, returns a white-tinted version for blue highlight backgrounds.
    func icon(for url: URL, isDirectory: Bool, selected: Bool = false) -> NSImage {
        if isDirectory {
            return folderIcon(for: url)
        }
        if selected {
            return fileIconSelected(for: url)
        }
        return fileIcon(for: url)
    }

    private func folderIcon(for url: URL) -> NSImage {
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private func fileIcon(for url: URL) -> NSImage {
        let filename = url.lastPathComponent.lowercased()
        let ext = url.pathExtension.lowercased()

        // Check exact filename first
        if let iconName = Self.nameMap[filename], let img = loadSVG(iconName) {
            return img
        }

        // Check extension
        if let iconName = Self.extMap[ext], let img = loadSVG(iconName) {
            return img
        }

        // Default file icon
        if let img = loadSVG("_file") {
            return img
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private func fileIconSelected(for url: URL) -> NSImage {
        let filename = url.lastPathComponent.lowercased()
        let ext = url.pathExtension.lowercased()

        if let iconName = Self.nameMap[filename], let img = loadSVGWhite(iconName) {
            return img
        }
        if let iconName = Self.extMap[ext], let img = loadSVGWhite(iconName) {
            return img
        }
        if let img = loadSVGWhite("_file") {
            return img
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    // MARK: - SVG Loading

    private func loadSVG(_ name: String) -> NSImage? {
        if let cached = cache[name] {
            return cached
        }

        guard let url = Bundle.module.url(forResource: name, withExtension: "svg", subdirectory: "Icons") else {
            return nil
        }

        guard let data = try? Data(contentsOf: url),
              let svgString = String(data: data, encoding: .utf8) else {
            return nil
        }

        // Scale SVG to desired size for crisp rendering
        let scaledSVG = svgString.replacingOccurrences(of: "width=\"16\"", with: "width=\"32\"")
            .replacingOccurrences(of: "height=\"16\"", with: "height=\"32\"")

        guard let scaledData = scaledSVG.data(using: .utf8),
              let nsImage = NSImage(data: scaledData) else {
            return nil
        }

        nsImage.size = NSSize(width: 16, height: 16)
        cache[name] = nsImage
        return nsImage
    }

    private func loadSVGWhite(_ name: String) -> NSImage? {
        let key = name + "_white"
        if let cached = cache[key] {
            return cached
        }

        guard let url = Bundle.module.url(forResource: name, withExtension: "svg", subdirectory: "Icons") else {
            return nil
        }

        guard let data = try? Data(contentsOf: url),
              var svgString = String(data: data, encoding: .utf8) else {
            return nil
        }

        // Replace all stroke/fill colors with white
        guard let colorPattern = try? NSRegularExpression(pattern: "#[0-9a-fA-F]{6}") else { return nil }
        svgString = colorPattern.stringByReplacingMatches(
            in: svgString,
            range: NSRange(svgString.startIndex..., in: svgString),
            withTemplate: "#ffffff"
        )

        let scaledSVG = svgString.replacingOccurrences(of: "width=\"16\"", with: "width=\"32\"")
            .replacingOccurrences(of: "height=\"16\"", with: "height=\"32\"")

        guard let scaledData = scaledSVG.data(using: .utf8),
              let nsImage = NSImage(data: scaledData) else {
            return nil
        }

        nsImage.size = NSSize(width: 16, height: 16)
        cache[key] = nsImage
        return nsImage
    }
}
