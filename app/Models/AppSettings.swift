import Foundation
import SwiftUI

@MainActor
class AppSettings: ObservableObject {
    static let shared = AppSettings()

    static let configBase = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/dux-file-explorer")
    private let configDir = AppSettings.configBase
    private let configFile: URL
    private var isLoading = false
    private var saveTask: Task<Void, Never>?

    @Published var previewFontSize: CGFloat {
        didSet { saveAsync() }
    }

    @Published var previewPaneSplit: CGFloat {
        didSet { saveAsync() }
    }

    @Published var showPreviewPane: Bool {
        didSet { saveAsync() }
    }

    @Published var leftPaneWidth: CGFloat {
        didSet { saveAsync() }
    }

    @Published var rightPaneWidth: CGFloat {
        didSet { saveAsync() }
    }

    @Published var browserViewMode: String {
        didSet { saveAsync() }
    }

    // Window position and size
    @Published var windowX: CGFloat? {
        didSet { saveAsync() }
    }
    @Published var windowY: CGFloat? {
        didSet { saveAsync() }
    }
    @Published var windowWidth: CGFloat? {
        didSet { saveAsync() }
    }
    @Published var windowHeight: CGFloat? {
        didSet { saveAsync() }
    }

    // Preferred apps per file type (extension or "__folder__")
    // Key: file extension (lowercase) or "__folder__"
    // Value: array of app bundle paths
    @Published var preferredApps: [String: [String]] = [:] {
        didSet { saveAsync() }
    }

    // Default folder handler (use this app instead of Finder)
    @Published var defaultFolderHandler: Bool {
        didSet { saveAsync() }
    }

    // OMDB API key for movie preview
    @Published var omdbAPIKey: String {
        didSet { saveAsync() }
    }

    private init() {
        configFile = configDir.appendingPathComponent("settings.json")

        // Default values
        previewFontSize = 12
        previewPaneSplit = 0.5
        showPreviewPane = true
        leftPaneWidth = 200
        rightPaneWidth = 260
        browserViewMode = "files"
        windowX = nil
        windowY = nil
        windowWidth = nil
        windowHeight = nil
        preferredApps = [:]
        defaultFolderHandler = false
        omdbAPIKey = ""

        // Migrate from old config path
        migrateOldConfig()

        // Load saved settings
        isLoading = true
        load()
        isLoading = false
    }

    private func migrateOldConfig() {
        let fm = FileManager.default
        let oldDir = fm.homeDirectoryForCurrentUser.appendingPathComponent(".config/dux-finder")
        let oldFile = oldDir.appendingPathComponent("settings.json")

        // Ensure new config dir exists
        try? fm.createDirectory(at: configDir, withIntermediateDirectories: true)

        // Migrate settings.json if old exists and new doesn't
        if fm.fileExists(atPath: oldFile.path) && !fm.fileExists(atPath: configFile.path) {
            try? fm.copyItem(at: oldFile, to: configFile)
        }

        // Clean up old dir if empty or only has settings.json
        if fm.fileExists(atPath: oldDir.path) {
            let contents = (try? fm.contentsOfDirectory(atPath: oldDir.path)) ?? []
            if contents.isEmpty || contents == ["settings.json"] {
                try? fm.removeItem(at: oldDir)
            }
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: configFile.path),
              let data = try? Data(contentsOf: configFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        if let fontSize = json["previewFontSize"] as? CGFloat {
            previewFontSize = fontSize
        }
        if let split = json["previewPaneSplit"] as? CGFloat {
            previewPaneSplit = split
        }
        if let apps = json["preferredApps"] as? [String: [String]] {
            preferredApps = apps
        }
        if let showPreview = json["showPreviewPane"] as? Bool {
            showPreviewPane = showPreview
        }
        if let leftWidth = json["leftPaneWidth"] as? CGFloat {
            leftPaneWidth = leftWidth
        }
        if let rightWidth = json["rightPaneWidth"] as? CGFloat {
            rightPaneWidth = rightWidth
        }
        if let viewMode = json["browserViewMode"] as? String {
            // Don't restore Search tab — always start on Files
            if viewMode.lowercased() != "search" {
                browserViewMode = viewMode
            }
        }
        if let x = json["windowX"] as? CGFloat {
            windowX = x
        }
        if let y = json["windowY"] as? CGFloat {
            windowY = y
        }
        if let w = json["windowWidth"] as? CGFloat {
            windowWidth = w
        }
        if let h = json["windowHeight"] as? CGFloat {
            windowHeight = h
        }
        if let folderHandler = json["defaultFolderHandler"] as? Bool {
            defaultFolderHandler = folderHandler
        }
        if let key = json["omdbAPIKey"] as? String {
            omdbAPIKey = key
        }
    }

    private func saveAsync() {
        guard !isLoading else { return }

        // Cancel previous pending save (debounce)
        saveTask?.cancel()

        let snapshot = SettingsSnapshot(
            configDir: configDir,
            configFile: configFile,
            fontSize: previewFontSize,
            split: previewPaneSplit,
            showPreview: showPreviewPane,
            leftWidth: leftPaneWidth,
            rightWidth: rightPaneWidth,
            viewMode: browserViewMode,
            winX: windowX,
            winY: windowY,
            winW: windowWidth,
            winH: windowHeight,
            apps: preferredApps,
            folderHandler: defaultFolderHandler,
            omdbKey: omdbAPIKey
        )

        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            Self.writeToDisk(snapshot)
        }
    }

    private struct SettingsSnapshot: Sendable {
        let configDir: URL
        let configFile: URL
        let fontSize: CGFloat
        let split: CGFloat
        let showPreview: Bool
        let leftWidth: CGFloat
        let rightWidth: CGFloat
        let viewMode: String
        let winX: CGFloat?
        let winY: CGFloat?
        let winW: CGFloat?
        let winH: CGFloat?
        let apps: [String: [String]]
        let folderHandler: Bool
        let omdbKey: String
    }

    nonisolated private static func writeToDisk(_ s: SettingsSnapshot) {
        try? FileManager.default.createDirectory(at: s.configDir, withIntermediateDirectories: true)

        var json: [String: Any] = [
            "previewFontSize": s.fontSize,
            "previewPaneSplit": s.split,
            "showPreviewPane": s.showPreview,
            "leftPaneWidth": s.leftWidth,
            "rightPaneWidth": s.rightWidth,
            "browserViewMode": s.viewMode,
            "preferredApps": s.apps
        ]

        if let x = s.winX { json["windowX"] = x }
        if let y = s.winY { json["windowY"] = y }
        if let w = s.winW { json["windowWidth"] = w }
        if let h = s.winH { json["windowHeight"] = h }

        json["defaultFolderHandler"] = s.folderHandler
        json["omdbAPIKey"] = s.omdbKey

        if let data = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted) {
            try? data.write(to: s.configFile)
        }
    }

    // Normalize file type: use "__empty__" for files without extension
    private func normalizeFileType(_ fileType: String) -> String {
        let trimmed = fileType.lowercased()
        return trimmed.isEmpty ? "__empty__" : trimmed
    }

    func addPreferredApp(for fileType: String, appPath: String) {
        let key = normalizeFileType(fileType)
        var apps = preferredApps[key] ?? []
        if !apps.contains(appPath) {
            apps.insert(appPath, at: 0)
            preferredApps[key] = apps
        }
    }

    func removePreferredApp(for fileType: String, appPath: String) {
        let key = normalizeFileType(fileType)
        var apps = preferredApps[key] ?? []
        apps.removeAll { $0 == appPath }
        if apps.isEmpty {
            preferredApps.removeValue(forKey: key)
        } else {
            preferredApps[key] = apps
        }
    }

    func getPreferredApps(for fileType: String) -> [String] {
        let key = normalizeFileType(fileType)
        return preferredApps[key] ?? []
    }

    func increaseFontSize() {
        previewFontSize = min(previewFontSize + 1, 32)
    }

    func decreaseFontSize() {
        previewFontSize = max(previewFontSize - 1, 8)
    }
}
