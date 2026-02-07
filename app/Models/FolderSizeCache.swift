import Foundation

final class FolderSizeCache: @unchecked Sendable {
    static let shared = FolderSizeCache()

    private var cache: [String: CacheEntry] = [:]
    private let cacheFile: URL
    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.dux.file-explorer.cache", attributes: .concurrent)
    private var saveWorkItem: DispatchWorkItem?

    struct CacheEntry: Codable {
        let size: UInt64
        let modificationDate: Date
    }

    private init() {
        let tmpDir = fileManager.temporaryDirectory
        let cacheDir = tmpDir.appendingPathComponent("com.dux.file-explorer")
        try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        cacheFile = cacheDir.appendingPathComponent("folder-sizes.json")
        loadCacheSync()
    }

    private func loadCacheSync() {
        guard let data = try? Data(contentsOf: cacheFile),
              let decoded = try? JSONDecoder().decode([String: CacheEntry].self, from: data) else {
            return
        }
        cache = decoded
    }

    private func saveCacheSync() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: cacheFile, options: .atomic)
    }

    func getCachedSize(for url: URL) -> UInt64? {
        var result: UInt64?
        queue.sync {
            guard let entry = cache[url.path] else { return }

            // Check if folder was modified since cache
            guard let attrs = try? fileManager.attributesOfItem(atPath: url.path),
                  let modDate = attrs[.modificationDate] as? Date else {
                return
            }

            if modDate <= entry.modificationDate {
                result = entry.size
            }
        }
        return result
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [self] in
            saveCacheSync()
        }
        saveWorkItem = item
        queue.asyncAfter(deadline: .now() + 1.0, flags: .barrier) { item.perform() }
    }

    func setCachedSize(for url: URL, size: UInt64) {
        queue.async(flags: .barrier) { [self] in
            guard let attrs = try? fileManager.attributesOfItem(atPath: url.path),
                  let modDate = attrs[.modificationDate] as? Date else {
                return
            }

            cache[url.path] = CacheEntry(size: size, modificationDate: modDate)
            scheduleSave()
        }
    }

    func invalidate(for url: URL) {
        queue.async(flags: .barrier) { [self] in
            cache.removeValue(forKey: url.path)
            scheduleSave()
        }
    }

    func clearAll() {
        queue.async(flags: .barrier) { [self] in
            cache.removeAll()
            saveCacheSync()
        }
    }
}
