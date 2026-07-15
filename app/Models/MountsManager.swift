import Foundation
import NetFS

struct FavoriteMount: Codable, Identifiable, Equatable {
    let name: String
    let urlString: String

    var id: String { urlString }
    var url: URL? { URL(string: urlString) }
    var normalizedKey: String? { url.map(MountsManager.normalizeRemote) }
}

struct MountError: Error {
    let status: Int32

    // ECANCELED / classic userCanceledErr -- user dismissed the auth dialog
    var isUserCancelled: Bool { status == 89 || status == -128 }

    var message: String {
        if status == 17 { return "Already mounted" }
        if status > 0 { return "Mount failed: " + String(cString: strerror(status)) }
        return "Mount failed (error \(status))"
    }
}

/// Favorite network mounts + NetFS connect. Favorites persist to mounts.json
/// and are matched to live volumes via their remount URL, so a favorite that
/// is currently mounted shows up as a regular volume row.
@MainActor
class MountsManager: ObservableObject {
    static let shared = MountsManager()

    @Published var favorites: [FavoriteMount] = []
    @Published var connectingURLs: Set<String> = []

    private let mountsFile: URL
    private let fileManager = FileManager.default

    private init() {
        mountsFile = AppSettings.configBase.appendingPathComponent("mounts.json")
        load()
    }

    // MARK: - Favorites

    func favorite(for volume: VolumeInfo) -> FavoriteMount? {
        guard let remote = volume.remoteURL else { return nil }
        let key = Self.normalizeRemote(remote)
        return favorites.first { $0.normalizedKey == key }
    }

    func addFavorite(name: String, urlString: String) {
        guard let url = URL(string: urlString) else { return }
        let key = Self.normalizeRemote(url)
        guard !favorites.contains(where: { $0.normalizedKey == key }) else { return }
        favorites.append(FavoriteMount(name: name, urlString: urlString))
        save()
    }

    func removeFavorite(_ favorite: FavoriteMount) {
        favorites.removeAll { $0.id == favorite.id }
        save()
    }

    func toggleFavorite(for volume: VolumeInfo) {
        if let existing = favorite(for: volume) {
            removeFavorite(existing)
        } else if let remote = volume.remoteURL {
            addFavorite(name: volume.name, urlString: remote.absoluteString)
        }
    }

    /// Favorites whose server is not currently mounted (shown as reconnect rows).
    func disconnectedFavorites(mounted volumes: [VolumeInfo]) -> [FavoriteMount] {
        let mountedKeys = Set(volumes.compactMap { $0.remoteURL.map(Self.normalizeRemote) })
        return favorites.filter { fav in
            guard let key = fav.normalizedKey else { return true }
            return !mountedKeys.contains(key)
        }
    }

    // MARK: - Connect

    /// Accepts bare "host/share" input the way Finder does; sftp:// is an
    /// alias for the ssh backend.
    nonisolated static func resolveServerURLString(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("sftp://") { return "ssh://" + trimmed.dropFirst("sftp://".count) }
        return trimmed.contains("://") ? trimmed : "smb://\(trimmed)"
    }

    /// Mounts the server URL (or reuses an existing mount) and returns the
    /// local mount point. ssh URLs don't mount: the SFTP backend connects and
    /// the returned URL is browsed directly. Shows a toast and returns nil on
    /// failure.
    func connect(_ urlString: String) async -> URL? {
        guard let url = URL(string: urlString), url.host != nil else {
            ToastManager.shared.showError("Invalid server URL")
            return nil
        }

        if url.scheme == "ssh" {
            guard let source = SourceRegistry.shared.source(for: url) as? SSHFileSource else {
                ToastManager.shared.showError("Invalid SSH URL")
                return nil
            }
            connectingURLs.insert(urlString)
            defer { connectingURLs.remove(urlString) }
            do {
                let target = try await source.connectAndResolve(url)
                ToastManager.shared.show("Connected \(url.host ?? "server")")
                return target
            } catch {
                ToastManager.shared.showError(error.localizedDescription)
                return nil
            }
        }

        // Already mounted -- just hand back the existing mount point
        let key = Self.normalizeRemote(url)
        if let existing = VolumesManager.shared.volumes.first(where: { $0.remoteURL.map(Self.normalizeRemote) == key }) {
            return existing.url
        }

        connectingURLs.insert(urlString)
        defer { connectingURLs.remove(urlString) }

        do {
            let path = try await Self.mount(url)
            VolumesManager.shared.loadVolumes()
            ToastManager.shared.show("Connected \(url.host ?? url.absoluteString)")
            return URL(fileURLWithPath: path)
        } catch let error as MountError {
            if !error.isUserCancelled {
                ToastManager.shared.showError(error.message)
            }
            return nil
        } catch {
            ToastManager.shared.showError("Mount failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Same NetFS API Finder's Cmd+K uses: native auth dialog, keychain, mounts under /Volumes.
    nonisolated private static func mount(_ url: URL) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let openOptions = NSMutableDictionary()
            openOptions[kNAUIOptionKey] = kNAUIOptionAllowUI

            var requestID: AsyncRequestID?
            let rc = NetFSMountURLAsync(
                url as CFURL,
                nil, nil, nil,
                openOptions as CFMutableDictionary,
                nil,
                &requestID,
                DispatchQueue.global(qos: .userInitiated)
            ) { status, _, mountpoints in
                if status == 0, let path = (mountpoints as? [String])?.first {
                    continuation.resume(returning: path)
                } else {
                    continuation.resume(throwing: MountError(status: status == 0 ? -1 : status))
                }
            }
            // Non-zero return means the async operation never started (callback won't fire)
            if rc != 0 {
                continuation.resume(throwing: MountError(status: rc))
            }
        }
    }

    /// Scheme/host/port/path identity, ignoring user info, case, and trailing slash.
    nonisolated static func normalizeRemote(_ url: URL) -> String {
        let scheme = (url.scheme ?? "").lowercased()
        let host = (url.host ?? "").lowercased()
        let port = url.port.map { ":\($0)" } ?? ""
        var path = url.path
        while path.hasSuffix("/") { path = String(path.dropLast()) }
        return "\(scheme)://\(host)\(port)\(path)"
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: mountsFile) else { return }
        favorites = (try? JSONDecoder().decode([FavoriteMount].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(favorites) else { return }
        try? data.write(to: mountsFile, options: .atomic)
    }
}
