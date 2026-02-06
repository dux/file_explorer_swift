import Foundation

/// Represents a file from any source (local filesystem or iPhone)
enum FileSource: Hashable {
    case local
    case iPhone(deviceId: String, appId: String, appName: String)
}

/// Unified file item that can represent local or iPhone files
struct FileItem: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String  // Local path or iPhone path
    let isDirectory: Bool
    let size: Int64
    let modifiedDate: Date?
    let source: FileSource

    // For local files
    var localURL: URL? {
        guard case .local = source else { return nil }
        return URL(fileURLWithPath: path)
    }

    // Display path
    var displayPath: String {
        switch source {
        case .local:
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            if path.hasPrefix(home) {
                return "~" + path.dropFirst(home.count)
            }
            return path
        case .iPhone(_, _, let appName):
            return "iPhone: \(appName)\(path)"
        }
    }

    // Create from local URL
    static func fromLocal(_ url: URL) -> FileItem? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return nil }

        var size: Int64 = 0
        var modDate: Date?

        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
            size = attrs[.size] as? Int64 ?? 0
            modDate = attrs[.modificationDate] as? Date
        }

        return FileItem(
            id: url.path,
            name: url.lastPathComponent,
            path: url.path,
            isDirectory: isDir.boolValue,
            size: size,
            modifiedDate: modDate,
            source: .local
        )
    }

    // Create from iPhone file
    static func fromIPhone(_ file: iPhoneFile, deviceId: String, appId: String, appName: String) -> FileItem {
        return FileItem(
            id: "iphone:\(deviceId):\(appId):\(file.path)",
            name: file.name,
            path: file.path,
            isDirectory: file.isDirectory,
            size: file.size,
            modifiedDate: file.modifiedDate,
            source: .iPhone(deviceId: deviceId, appId: appId, appName: appName)
        )
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: FileItem, rhs: FileItem) -> Bool {
        lhs.id == rhs.id
    }
}

/// Global selection manager that handles files from any source
@MainActor
class SelectionManager: ObservableObject {
    static let shared = SelectionManager()

    @Published private(set) var items: Set<FileItem> = []
    @Published var version: Int = 0

    private init() {}

    var count: Int { items.count }
    var isEmpty: Bool { items.isEmpty }

    var localItems: [FileItem] {
        items.filter { if case .local = $0.source { return true } else { return false } }
    }

    var iPhoneItems: [FileItem] {
        items.filter { if case .iPhone = $0.source { return true } else { return false } }
    }

    func add(_ item: FileItem) {
        let inserted = items.insert(item).inserted
        if inserted {
            version += 1
            ToastManager.shared.show("Added to selection (\(count) item\(count == 1 ? "" : "s"))")
        }
    }

    func addLocal(_ url: URL) {
        if let item = FileItem.fromLocal(url) {
            add(item)
        }
    }

    func addIPhone(_ file: iPhoneFile, deviceId: String, appId: String, appName: String) {
        let item = FileItem.fromIPhone(file, deviceId: deviceId, appId: appId, appName: appName)
        add(item)
    }

    func remove(_ item: FileItem) {
        items.remove(item)
        version += 1
    }

    func contains(_ item: FileItem) -> Bool {
        items.contains(item)
    }

    func containsLocal(_ url: URL) -> Bool {
        items.contains { $0.path == url.path && $0.source == .local }
    }

    func containsIPhone(path: String, deviceId: String, appId: String) -> Bool {
        items.contains {
            if case .iPhone(let did, let aid, _) = $0.source {
                return $0.path == path && did == deviceId && aid == appId
            }
            return false
        }
    }

    func toggle(_ item: FileItem) {
        if contains(item) {
            remove(item)
        } else {
            add(item)
        }
    }

    func removeByPath(_ path: String) {
        let before = items.count
        items = items.filter { $0.path != path }
        if items.count != before {
            version += 1
        }
    }

    func updateLocalPath(from oldPath: String, to newPath: String) {
        guard let oldItem = items.first(where: { $0.path == oldPath && $0.source == .local }) else { return }

        items.remove(oldItem)
        if let newItem = FileItem.fromLocal(URL(fileURLWithPath: newPath)) {
            items.insert(newItem)
        }
        version += 1
    }

    func clear() {
        items.removeAll()
        version += 1
        ToastManager.shared.show("Selection cleared")
    }

    // MARK: - Operations

    /// Copy/move iPhone files to a local destination
    func downloadIPhoneItems(to destination: URL, move: Bool = false) async -> Int {
        var count = 0
        let iPhoneManager = iPhoneManager.shared

        for item in iPhoneItems {
            guard case .iPhone(let deviceId, let appId, _) = item.source else { continue }

            let destPath = destination.appendingPathComponent(item.name)

            let success = await iPhoneManager.downloadFileFromContext(
                deviceId: deviceId,
                appId: appId,
                remotePath: item.path,
                to: destPath
            )

            if success {
                count += 1
                if move {
                    await iPhoneManager.deleteFileFromContext(
                        deviceId: deviceId,
                        appId: appId,
                        remotePath: item.path
                    )
                    remove(item)
                }
            }
        }

        return count
    }

    /// Upload local files to iPhone destination
    func uploadLocalItems(deviceId: String, appId: String, toPath: String) async -> Int {
        var count = 0
        let iPhoneManager = iPhoneManager.shared

        for item in localItems {
            guard let url = item.localURL else { continue }

            let success = await iPhoneManager.uploadFileFromContext(
                deviceId: deviceId,
                appId: appId,
                localURL: url,
                toPath: toPath
            )

            if success {
                count += 1
            }
        }

        return count
    }

    /// Delete all selected items
    func deleteAll() async -> Int {
        var count = 0
        let iPhoneManager = iPhoneManager.shared
        let fm = FileManager.default

        for item in items {
            switch item.source {
            case .local:
                do {
                    try fm.trashItem(at: URL(fileURLWithPath: item.path), resultingItemURL: nil)
                    count += 1
                } catch {
                    ToastManager.shared.showError("Failed to trash \(item.name): \(error.localizedDescription)")
                }

            case .iPhone(let deviceId, let appId, _):
                let success = await iPhoneManager.deleteFileFromContext(
                    deviceId: deviceId,
                    appId: appId,
                    remotePath: item.path
                )
                if success { count += 1 }
            }
        }

        clear()
        return count
    }

    /// Move local items to local destination
    func moveLocalItems(to destination: URL) -> Int {
        var count = 0
        let fm = FileManager.default

        for item in localItems {
            guard let url = item.localURL else { continue }
            let destPath = destination.appendingPathComponent(item.name)

            do {
                try fm.moveItem(at: url, to: destPath)
                count += 1
                remove(item)
            } catch {
                ToastManager.shared.showError("Failed to move \(item.name): \(error.localizedDescription)")
            }
        }

        return count
    }

    /// Copy local items to local destination
    func copyLocalItems(to destination: URL) -> Int {
        var count = 0
        let fm = FileManager.default

        for item in localItems {
            guard let url = item.localURL else { continue }
            let destPath = destination.appendingPathComponent(item.name)

            do {
                try fm.copyItem(at: url, to: destPath)
                count += 1
            } catch {
                ToastManager.shared.showError("Failed to copy \(item.name): \(error.localizedDescription)")
            }
        }

        return count
    }
}
