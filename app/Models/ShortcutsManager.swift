import Foundation

@MainActor
class ShortcutsManager: ObservableObject {
    @Published var customFolders: [URL] = []

    private let configDirectory: URL
    private let foldersFile: URL
    private let fileManager = FileManager.default

    static let shared = ShortcutsManager()

    private init() {
        configDirectory = AppSettings.configBase
        foldersFile = configDirectory.appendingPathComponent("folders.txt")

        createConfigDirectoryIfNeeded()
        migrateOldConfig()
        loadCustomFolders()
    }

    /// Test-only initializer with custom config path
    internal init(configDir: URL) {
        configDirectory = configDir
        foldersFile = configDir.appendingPathComponent("folders.txt")
        createConfigDirectoryIfNeeded()
        loadCustomFolders()
    }

    private func migrateOldConfig() {
        let oldDir = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".dux-file-explorer")
        let oldFile = oldDir.appendingPathComponent("folders.txt")

        if fileManager.fileExists(atPath: oldFile.path) && !fileManager.fileExists(atPath: foldersFile.path) {
            try? fileManager.copyItem(at: oldFile, to: foldersFile)
        }

        // Clean up old dir if empty or only has folders.txt
        if fileManager.fileExists(atPath: oldDir.path) {
            let contents = (try? fileManager.contentsOfDirectory(atPath: oldDir.path)) ?? []
            if contents.isEmpty || contents == ["folders.txt"] {
                try? fileManager.removeItem(at: oldDir)
            }
        }
    }

    var allShortcuts: [ShortcutItem] {
        var items: [ShortcutItem] = []
        let home = fileManager.homeDirectoryForCurrentUser

        items.append(ShortcutItem(url: home, name: "Home", isBuiltIn: true, icon: "house.fill"))
        items.append(ShortcutItem(url: home.appendingPathComponent("Desktop"), name: "Desktop", isBuiltIn: true, icon: "menubar.dock.rectangle"))
        items.append(ShortcutItem(url: home.appendingPathComponent("Downloads"), name: "Downloads", isBuiltIn: true, icon: "arrow.down.circle.fill"))
        items.append(ShortcutItem(url: URL(fileURLWithPath: "/Applications"), name: "Applications", isBuiltIn: true, icon: "square.grid.2x2.fill"))

        for folder in customFolders {
            let isProject = fileManager.fileExists(atPath: folder.appendingPathComponent("README.md").path)
                || fileManager.fileExists(atPath: folder.appendingPathComponent("README.MD").path)
                || fileManager.fileExists(atPath: folder.appendingPathComponent("readme.md").path)
            items.append(ShortcutItem(url: folder, name: folder.lastPathComponent, isBuiltIn: false, icon: isProject ? "chevron.left.forwardslash.chevron.right" : nil))
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
    var id: String { url.path }
    let url: URL
    let name: String
    let isBuiltIn: Bool
    var icon: String? = nil
}
