import Foundation

struct AppUninstaller {
    /// Find all data directories/files left by an .app bundle
    static func findAppData(for appURL: URL) -> [URL] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let library = home.appendingPathComponent("Library")

        // Read bundle identifier and name from Info.plist
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        var bundleId: String?
        var appName = appURL.deletingPathExtension().lastPathComponent

        if let data = try? Data(contentsOf: plistURL),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            bundleId = plist["CFBundleIdentifier"] as? String
            if let name = plist["CFBundleName"] as? String {
                appName = name
            }
        }

        var paths: [URL] = []
        var seen = Set<String>()

        func addIfExists(_ url: URL) {
            guard fm.fileExists(atPath: url.path), !seen.contains(url.path) else { return }
            seen.insert(url.path)
            paths.append(url)
        }

        // Search by bundle ID
        if let bid = bundleId {
            let bundleIdLocations: [(String, String)] = [
                ("Application Support", bid),
                ("Preferences", "\(bid).plist"),
                ("Caches", bid),
                ("HTTPStorages", bid),
                ("WebKit", bid),
                ("Saved Application State", "\(bid).savedState"),
                ("Containers", bid),
                ("Logs", bid),
            ]

            for (subdir, name) in bundleIdLocations {
                addIfExists(library.appendingPathComponent(subdir).appendingPathComponent(name))
            }

            // Group Containers (pattern: *bundleId*)
            let groupDir = library.appendingPathComponent("Group Containers")
            if let entries = try? fm.contentsOfDirectory(atPath: groupDir.path) {
                for entry in entries where entry.contains(bid) {
                    addIfExists(groupDir.appendingPathComponent(entry))
                }
            }
        }

        // Search by app name
        let nameLocations = [
            "Application Support",
            "Caches",
        ]
        for subdir in nameLocations {
            addIfExists(library.appendingPathComponent(subdir).appendingPathComponent(appName))
        }

        return paths.sorted { $0.path < $1.path }
    }
}
