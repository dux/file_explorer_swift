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

    // Recently used apps (global, across all file types)
    // Ordered most-recent-first, capped at 10
    @Published var recentlyUsedApps: [String] = [] {
        didSet { saveAsync() }
    }

    // Default folder handler (use this app instead of Finder)
    @Published var defaultFolderHandler: Bool {
        didSet { saveAsync() }
    }

    // Flat folders mode (compact breadcrumb instead of ancestor tree)
    @Published var flatFolders: Bool {
        didSet { saveAsync() }
    }

    // OMDB API key for movie preview
    @Published var omdbAPIKey: String {
        didSet { saveAsync() }
    }

    // Font sizes for text styles
    @Published var fontDefault: CGFloat {
        didSet { saveAsync() }
    }
    @Published var fontButtons: CGFloat {
        didSet { saveAsync() }
    }
    @Published var fontSmall: CGFloat {
        didSet { saveAsync() }
    }
    @Published var fontTitle: CGFloat {
        didSet { saveAsync() }
    }

    private init() {
        configFile = configDir.appendingPathComponent("settings.json")

        // Default values
        previewFontSize = 14
        previewPaneSplit = 0.5
        showPreviewPane = true
        leftPaneWidth = 326
        rightPaneWidth = 532
        browserViewMode = "files"
        windowX = nil
        windowY = nil
        windowWidth = nil
        windowHeight = nil
        preferredApps = [:]
        defaultFolderHandler = false
        flatFolders = false
        omdbAPIKey = ""
        fontDefault = 14
        fontButtons = 12
        fontSmall = 12
        fontTitle = 13

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
        if let flat = json["flatFolders"] as? Bool {
            flatFolders = flat
        }
        if let key = json["omdbAPIKey"] as? String {
            omdbAPIKey = key
        }
        if let recent = json["recentlyUsedApps"] as? [String] {
            recentlyUsedApps = recent
        }
        if let v = json["fontDefault"] as? CGFloat { fontDefault = v }
        if let v = json["fontButtons"] as? CGFloat { fontButtons = v }
        if let v = json["fontSmall"] as? CGFloat { fontSmall = v }
        if let v = json["fontTitle"] as? CGFloat { fontTitle = v }
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
            flatFolders: flatFolders,
            omdbKey: omdbAPIKey,
            recentApps: recentlyUsedApps,
            fontDefault: fontDefault,
            fontButtons: fontButtons,
            fontSmall: fontSmall,
            fontTitle: fontTitle
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
        let flatFolders: Bool
        let omdbKey: String
        let recentApps: [String]
        let fontDefault: CGFloat
        let fontButtons: CGFloat
        let fontSmall: CGFloat
        let fontTitle: CGFloat
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
        json["flatFolders"] = s.flatFolders
        json["omdbAPIKey"] = s.omdbKey
        json["recentlyUsedApps"] = s.recentApps
        json["fontDefault"] = s.fontDefault
        json["fontButtons"] = s.fontButtons
        json["fontSmall"] = s.fontSmall
        json["fontTitle"] = s.fontTitle

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

    func movePreferredApp(for fileType: String, from source: IndexSet, to destination: Int) {
        let key = normalizeFileType(fileType)
        guard var apps = preferredApps[key], !apps.isEmpty else { return }
        apps.move(fromOffsets: source, toOffset: destination)
        preferredApps[key] = apps
    }

    func getPreferredApps(for fileType: String) -> [String] {
        let key = normalizeFileType(fileType)
        return preferredApps[key] ?? []
    }

    func addRecentlyUsedApp(appPath: String) {
        var apps = recentlyUsedApps
        apps.removeAll { $0 == appPath }
        apps.insert(appPath, at: 0)
        if apps.count > 10 { apps = Array(apps.prefix(10)) }
        if recentlyUsedApps != apps { recentlyUsedApps = apps }
    }

    func increaseFontSize() {
        previewFontSize = min(previewFontSize + 1, 32)
    }

    func decreaseFontSize() {
        previewFontSize = max(previewFontSize - 1, 8)
    }
}
