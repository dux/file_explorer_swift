import Foundation
import SwiftUI
import CryptoKit

enum TagColor: String, CaseIterable, Identifiable {
    case red
    case blue
    case green
    case orange

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .red: return Color(red: 0.90, green: 0.45, blue: 0.45)
        case .blue: return Color(red: 0.45, green: 0.60, blue: 0.90)
        case .green: return Color(red: 0.40, green: 0.78, blue: 0.55)
        case .orange: return Color(red: 0.92, green: 0.68, blue: 0.38)
        }
    }

    var label: String {
        rawValue.capitalized
    }
}

struct TaggedFile: Identifiable {
    let url: URL
    let exists: Bool
    let isDirectory: Bool

    var id: String { url.path }
    var name: String { url.lastPathComponent }

    var parentPath: String {
        let path = url.deletingLastPathComponent().path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "~" }
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

@MainActor
class ColorTagManager: ObservableObject {
    static let shared = ColorTagManager()

    @Published var counts: [TagColor: Int] = [:]
    @Published var version: Int = 0

    var totalCount: Int {
        counts.values.reduce(0, +)
    }

    private let colorsDir: URL
    private let fm = FileManager.default

    private init() {
        colorsDir = AppSettings.configBase.appendingPathComponent("colors")
        ensureDirectories()
        reloadCounts()
    }

    private func ensureDirectories() {
        for color in TagColor.allCases {
            let dir = colorsDir.appendingPathComponent(color.rawValue)
            if !fm.fileExists(atPath: dir.path) {
                try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
    }

    private func sha1(_ string: String) -> String {
        let data = Data(string.utf8)
        let digest = Insecure.SHA1.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func linkPath(for url: URL, color: TagColor) -> URL {
        let hash = sha1(url.path)
        return colorsDir
            .appendingPathComponent(color.rawValue)
            .appendingPathComponent(hash)
    }

    func tagFile(_ url: URL, color: TagColor) {
        let link = linkPath(for: url, color: color)
        // Remove existing if any
        try? fm.removeItem(at: link)
        try? fm.createSymbolicLink(atPath: link.path, withDestinationPath: url.path)
        reloadCounts()
    }

    func untagFile(_ url: URL, color: TagColor) {
        let link = linkPath(for: url, color: color)
        try? fm.removeItem(at: link)
        reloadCounts()
    }

    func untagFile(_ url: URL) {
        for color in TagColor.allCases {
            untagFile(url, color: color)
        }
    }

    func colorsForFile(_ url: URL) -> [TagColor] {
        var result: [TagColor] = []
        for color in TagColor.allCases {
            let link = linkPath(for: url, color: color)
            if fm.fileExists(atPath: link.path) {
                result.append(color)
            }
        }
        return result
    }

    func isTagged(_ url: URL, color: TagColor) -> Bool {
        let link = linkPath(for: url, color: color)
        // fileExists follows symlinks, so we use attributesOfItem to check symlink itself
        return (try? fm.attributesOfItem(atPath: link.path)) != nil
    }

    func filesForColor(_ color: TagColor) -> [TaggedFile] {
        let dir = colorsDir.appendingPathComponent(color.rawValue)
        guard let entries = try? fm.contentsOfDirectory(atPath: dir.path) else { return [] }

        var files: [TaggedFile] = []
        for entry in entries {
            let linkURL = dir.appendingPathComponent(entry)
            guard let target = try? fm.destinationOfSymbolicLink(atPath: linkURL.path) else { continue }
            let targetURL = URL(fileURLWithPath: target)
            var isDir: ObjCBool = false
            let exists = fm.fileExists(atPath: target, isDirectory: &isDir)
            files.append(TaggedFile(url: targetURL, exists: exists, isDirectory: isDir.boolValue))
        }

        return files.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func reloadCounts() {
        var newCounts: [TagColor: Int] = [:]
        for color in TagColor.allCases {
            let dir = colorsDir.appendingPathComponent(color.rawValue)
            let entries = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
            newCounts[color] = entries.count
        }
        counts = newCounts
        version += 1
    }

    func toggleTag(_ url: URL, color: TagColor) {
        if isTagged(url, color: color) {
            untagFile(url, color: color)
        } else {
            tagFile(url, color: color)
        }
    }
}
