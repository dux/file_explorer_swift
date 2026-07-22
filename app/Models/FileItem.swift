import Foundation

/// Identifies the backend-specific location of a selected item.
enum FileSource: Hashable {
    case local
    case iPhone(deviceId: String, appId: String, appName: String)
    case remote(URL)
}

/// Unified representation of a selected file or folder from any backend.
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

    var remoteURL: URL? {
        guard case .remote(let url) = source else { return nil }
        return url
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
        case .remote(let url):
            return url.absoluteString.removingPercentEncoding ?? url.absoluteString
        }
    }

    // Create from local URL
    static func fromLocal(_ url: URL) -> Self? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return nil }

        var size: Int64 = 0
        var modDate: Date?

        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
            size = attrs[.size] as? Int64 ?? 0
            modDate = attrs[.modificationDate] as? Date
        }

        return Self(
            id: url.path,
            name: url.lastPathComponent,
            path: url.path,
            isDirectory: isDir.boolValue,
            size: size,
            modifiedDate: modDate,
            source: .local
        )
    }

    /// Build from a browser listing row, dispatching on the URL scheme.
    /// Local falls back to a disk stat (fromLocal); iPhone reconstructs the
    /// AFC context from the virtual URL.
    @MainActor
    static func from(info: CachedFileInfo) -> Self? {
        switch info.url.scheme {
        case nil, "file":
            return fromLocal(info.url)
        case "iphone":
            guard let udid = info.url.host,
                  let (bundleId, afcPath) = iPhoneFileSource.afcContext(for: info.url) else { return nil }
            let source = SourceRegistry.shared.source(for: info.url) as? iPhoneFileSource
            let file = iPhoneFile(
                name: info.name,
                path: afcPath,
                isDirectory: info.isDirectory,
                size: info.size,
                modifiedDate: info.modDate
            )
            return fromIPhone(file, deviceId: udid, appId: bundleId, appName: source?.appName(for: bundleId) ?? bundleId)
        default:
            return fromRemote(info)
        }
    }

    static func fromRemote(_ info: CachedFileInfo) -> Self {
        Self(
            id: info.url.absoluteString,
            name: info.name,
            path: info.url.path,
            isDirectory: info.isDirectory,
            size: info.size,
            modifiedDate: info.modDate,
            source: .remote(info.url)
        )
    }

    static func fromRemoteFolder(_ url: URL) -> Self {
        Self(
            id: url.absoluteString,
            name: url.lastPathComponent.isEmpty ? (url.host ?? url.absoluteString) : url.lastPathComponent,
            path: url.path,
            isDirectory: true,
            size: 0,
            modifiedDate: nil,
            source: .remote(url)
        )
    }

    // Create from iPhone file
    static func fromIPhone(_ file: iPhoneFile, deviceId: String, appId: String, appName: String) -> Self {
        return Self(
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

    static func == (lhs: Self, rhs: Self) -> Bool {
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

    var sortedItems: [FileItem] {
        Array(items).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var localItems: [FileItem] {
        items.filter { if case .local = $0.source { return true } else { return false } }
    }

    var iPhoneItems: [FileItem] {
        items.filter { if case .iPhone = $0.source { return true } else { return false } }
    }

    var remoteItems: [FileItem] {
        items.filter { if case .remote = $0.source { return true } else { return false } }
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

    /// Batch add local URLs without per-item toasts. Returns count of newly added items.
    func addLocals(_ urls: [URL]) -> Int {
        var added = 0
        for url in urls {
            if let item = FileItem.fromLocal(url) {
                if items.insert(item).inserted {
                    added += 1
                }
            }
        }
        if added > 0 {
            version += 1
        }
        return added
    }

    func addIPhone(_ file: iPhoneFile, deviceId: String, appId: String, appName: String) {
        let item = FileItem.fromIPhone(file, deviceId: deviceId, appId: appId, appName: appName)
        add(item)
    }

    /// Batch add without per-item toasts. Returns count of newly added items.
    func addItems(_ newItems: [FileItem]) -> Int {
        var added = 0
        for item in newItems where items.insert(item).inserted {
            added += 1
        }
        if added > 0 {
            version += 1
        }
        return added
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

    func containsRemote(_ url: URL) -> Bool {
        items.contains { $0.remoteURL == url }
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
        items = items.filter { $0.path != path || $0.source != .local }
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
        let itemsToDownload = iPhoneItems

        let progress = iPhoneTransferProgressManager.shared
        progress.start(direction: .download, total: itemsToDownload.count)

        for item in itemsToDownload {
            if progress.isCancelled { break }

            guard case .iPhone(let deviceId, let appId, _) = item.source else { continue }

            progress.update(file: item.name, completed: count)

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

        progress.finish()
        return count
    }

    /// Upload local files to iPhone destination
    func uploadLocalItems(deviceId: String, appId: String, toPath: String) async -> Int {
        var count = 0
        let iPhoneManager = iPhoneManager.shared
        let itemsToUpload = localItems

        let progress = iPhoneTransferProgressManager.shared
        progress.start(direction: .upload, total: itemsToUpload.count)

        for item in itemsToUpload {
            if progress.isCancelled { break }

            guard let url = item.localURL else { continue }

            progress.update(file: item.name, completed: count)

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

        progress.finish()
        return count
    }

    /// Delete all selected items. Local items are trashed on a background thread
    /// (with the running indicator); iPhone items are deleted over the wire.
    func deleteAll() async -> Int {
        let localURLs = localItems.compactMap { $0.localURL }
        let iPhone = iPhoneItems
        clear()

        var count = 0
        if !localURLs.isEmpty {
            count += await OperationManager.shared.run(title: "Moving to Trash") { trashURLs(localURLs) }
        }

        let iPhoneManager = iPhoneManager.shared
        for item in iPhone {
            guard case .iPhone(let deviceId, let appId, _) = item.source else { continue }
            let success = await iPhoneManager.deleteFileFromContext(
                deviceId: deviceId,
                appId: appId,
                remotePath: item.path
            )
            if success { count += 1 }
        }

        return count
    }

    /// Move the given local items to Trash on a background thread. Returns the
    /// number trashed; per-batch failures are reported via toast.
    func trashItems(_ items: [FileItem]) async -> Int {
        let urls = items.compactMap { $0.localURL }
        guard !urls.isEmpty else { return 0 }
        return await OperationManager.shared.run(title: "Moving to Trash") { trashURLs(urls) }
    }

    /// Move local items to a local destination on a background thread (with the
    /// running indicator). `items` is captured by the caller so the selection can be
    /// cleared immediately, mirroring `CopyProgressManager.copyItems`.
    func moveItems(_ items: [(name: String, url: URL)], to destination: URL) async -> Int {
        guard !items.isEmpty else { return 0 }
        return await OperationManager.shared.run(title: "Moving files") { () -> Int in
            let fm = FileManager.default
            var moved = 0
            for (name, url) in items {
                if Task.isCancelled { break }

                let destURL = uniqueLocalDestination(in: destination) { attempt in
                    numberedName(name, attempt: attempt)
                }

                do {
                    try fm.moveItem(at: url, to: destURL)
                    moved += 1
                } catch {
                    let msg = error.localizedDescription
                    let n = name
                    Task { @MainActor in ToastManager.shared.showError("Failed to move \(n): \(msg)") }
                }
            }
            return moved
        }
    }

}

/// First free URL in `directory`, trying `makeName(0)`, `makeName(1)`, ... in order.
/// Callable off the main actor; each call site owns its naming format.
func uniqueLocalDestination(in directory: URL, makeName: (Int) -> String) -> URL {
    let fm = FileManager.default
    var attempt = 0
    var url = directory.appendingPathComponent(makeName(attempt))
    while fm.fileExists(atPath: url.path) {
        attempt += 1
        url = directory.appendingPathComponent(makeName(attempt))
    }
    return url
}

/// Finder-style collision name: "name.ext", then "name 2.ext", "name 3.ext", ...
func numberedName(_ name: String, attempt: Int) -> String {
    guard attempt > 0 else { return name }
    let baseName = (name as NSString).deletingPathExtension
    let ext = (name as NSString).pathExtension
    let n = attempt + 1
    return ext.isEmpty ? "\(baseName) \(n)" : "\(baseName) \(n).\(ext)"
}

/// Trashes the given URLs off the main actor, returning how many succeeded.
/// Honours cancellation between items and reports the failure count via toast.
private func trashURLs(_ urls: [URL]) -> Int {
    let fm = FileManager.default
    var trashed = 0
    var failed = 0
    for url in urls {
        if Task.isCancelled { break }
        do {
            try fm.trashItem(at: url, resultingItemURL: nil)
            trashed += 1
        } catch {
            failed += 1
        }
    }
    if failed > 0 {
        let f = failed
        Task { @MainActor in ToastManager.shared.showError("Failed to trash \(f) item(s)") }
    }
    return trashed
}
