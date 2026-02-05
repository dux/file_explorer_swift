import Foundation

@MainActor
class ShortcutsManager: ObservableObject {
    @Published var customFolders: [URL] = []

    private let configDirectory: URL
    private let foldersFile: URL
    private let fileManager = FileManager.default

    static let shared = ShortcutsManager()

    private init() {
        let homeURL = fileManager.homeDirectoryForCurrentUser
        configDirectory = homeURL.appendingPathComponent(".dux-file-explorer")
        foldersFile = configDirectory.appendingPathComponent("folders.txt")

        createConfigDirectoryIfNeeded()
        loadCustomFolders()
    }

    var allShortcuts: [ShortcutItem] {
        var items: [ShortcutItem] = []
        let home = fileManager.homeDirectoryForCurrentUser

        items.append(ShortcutItem(url: home, name: "Home", isBuiltIn: true))
        items.append(ShortcutItem(url: home.appendingPathComponent("Desktop"), name: "Desktop", isBuiltIn: true))
        items.append(ShortcutItem(url: home.appendingPathComponent("Downloads"), name: "Downloads", isBuiltIn: true))
        items.append(ShortcutItem(url: URL(fileURLWithPath: "/Applications"), name: "Applications", isBuiltIn: true))
        items.append(ShortcutItem(url: home.appendingPathComponent(".Trash"), name: "Trash", isBuiltIn: true))

        for folder in customFolders {
            items.append(ShortcutItem(url: folder, name: folder.lastPathComponent, isBuiltIn: false))
        }

        return items
    }

    private func createConfigDirectoryIfNeeded() {
        if !fileManager.fileExists(atPath: configDirectory.path) {
            try? fileManager.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        }
    }

    private func loadCustomFolders() {
        guard fileManager.fileExists(atPath: foldersFile.path) else { return }

        guard let content = try? String(contentsOf: foldersFile, encoding: .utf8) else { return }

        customFolders = content.components(separatedBy: .newlines)
            .compactMap { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : URL(fileURLWithPath: trimmed)
            }
    }

    func saveCustomFolders() {
        let content = customFolders.map { $0.path }.joined(separator: "\n")
        try? content.write(to: foldersFile, atomically: true, encoding: .utf8)
    }

    func addFolder(_ url: URL) {
        guard !customFolders.contains(where: { $0.path == url.path }) else { return }
        customFolders.append(url)
        saveCustomFolders()
    }

    func removeFolder(_ url: URL) {
        customFolders.removeAll { $0.path == url.path }
        saveCustomFolders()
    }

    func moveFolder(from source: IndexSet, to destination: Int) {
        customFolders.move(fromOffsets: source, toOffset: destination)
        saveCustomFolders()
    }
}

struct ShortcutItem: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    let isBuiltIn: Bool
}
