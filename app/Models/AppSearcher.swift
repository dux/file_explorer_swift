import AppKit

struct AppInfo: @unchecked Sendable {
    let url: URL
    let name: String
    let icon: NSImage
}

@MainActor
final class AppSearcher {
    static let shared = AppSearcher()

    private var allApps: [AppInfo] = []
    private var isLoaded = false
    private var loadCallbacks: [() -> Void] = []
    private var isLoading = false

    private init() {}

    /// All discovered apps, sorted by name. Empty until loadAll() finishes.
    var apps: [AppInfo] { allApps }
    var loaded: Bool { isLoaded }

    /// Load all apps from standard directories. Safe to call multiple times.
    func loadAll(completion: (() -> Void)? = nil) {
        if isLoaded {
            completion?()
            return
        }

        if let cb = completion {
            loadCallbacks.append(cb)
        }

        guard !isLoading else { return }
        isLoading = true

        Task.detached(priority: .userInitiated) {
            let apps = Self.scanApps()
            await MainActor.run {
                self.allApps = apps
                self.isLoaded = true
                self.isLoading = false
                let cbs = self.loadCallbacks
                self.loadCallbacks.removeAll()
                for cb in cbs { cb() }
            }
        }
    }

    /// Search by name. Empty query returns all apps.
    func search(_ term: String) -> [AppInfo] {
        if term.isEmpty { return allApps }
        let query = term.lowercased()
        return allApps.filter { $0.name.lowercased().contains(query) }
    }

    /// Apps that can open a specific file (via Launch Services), limited to 15.
    func appsForFile(_ url: URL) -> [AppInfo] {
        var appURLs: [URL] = []
        if let apps = LSCopyApplicationURLsForURL(url as CFURL, .all)?.takeRetainedValue() as? [URL] {
            appURLs = apps
        }

        var seen = Set<String>()
        var result: [AppInfo] = []
        for appURL in appURLs {
            let name = appURL.deletingPathExtension().lastPathComponent
            guard !seen.contains(name) else { continue }
            seen.insert(name)
            let icon = NSWorkspace.shared.icon(forFile: appURL.path)
            result.append(AppInfo(url: appURL, name: name, icon: icon))
            if result.count >= 15 { break }
        }
        return result
    }

    // MARK: - Private

    nonisolated private static func scanApps() -> [AppInfo] {
        var apps: [AppInfo] = []
        var seen = Set<String>()

        let appDirs = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]

        let fm = FileManager.default
        for dir in appDirs {
            guard let enumerator = fm.enumerator(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for case let url as URL in enumerator {
                if url.pathExtension == "app" {
                    let name = url.deletingPathExtension().lastPathComponent
                    if !seen.contains(name) {
                        seen.insert(name)
                        let icon = NSWorkspace.shared.icon(forFile: url.path)
                        apps.append(AppInfo(url: url, name: name, icon: icon))
                    }
                    enumerator.skipDescendants()
                }
            }
        }

        apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return apps
    }
}
