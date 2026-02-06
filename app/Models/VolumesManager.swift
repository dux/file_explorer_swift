import Foundation
import AppKit

struct VolumeInfo: Identifiable, Equatable {
    let url: URL
    let name: String
    let isRemovable: Bool
    let isNetwork: Bool
    let isEjectable: Bool
    let totalCapacity: Int64
    let availableCapacity: Int64

    var id: String { url.path }

    var icon: String {
        if isNetwork { return "network" }
        if isRemovable { return "externaldrive.fill" }
        return "internaldrive.fill"
    }

    var iconColor: NSColor {
        if isNetwork { return .systemBlue }
        if isRemovable { return .systemOrange }
        return .systemGray
    }

    var capacityText: String {
        guard totalCapacity > 0 else { return "" }
        let used = totalCapacity - availableCapacity
        return "\(formatBytes(used)) / \(formatBytes(totalCapacity))"
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

@MainActor
class VolumesManager: ObservableObject {
    static let shared = VolumesManager()

    @Published var volumes: [VolumeInfo] = []

    nonisolated(unsafe) private var mountObserver: NSObjectProtocol?
    nonisolated(unsafe) private var unmountObserver: NSObjectProtocol?

    private init() {
        loadVolumes()
        startObserving()
    }

    func loadVolumes() {
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeIsLocalKey,
            .volumeIsRemovableKey,
            .volumeIsInternalKey,
            .volumeIsEjectableKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeURLForRemountingKey,
        ]

        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) else {
            volumes = []
            return
        }

        var result: [VolumeInfo] = []
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }

            let isInternal = values.volumeIsInternal ?? true
            let isRemovable = values.volumeIsRemovable ?? false
            let isEjectable = values.volumeIsEjectable ?? false
            let isLocal = values.volumeIsLocal ?? true
            let isNetwork = !isLocal
            let remountURL = values.volumeURLForRemounting

            // Skip the boot volume
            if url.path == "/" { continue }

            // Skip internal non-removable non-network volumes (system partitions)
            if isInternal && !isRemovable && !isNetwork && remountURL == nil { continue }

            let name = values.volumeName ?? url.lastPathComponent
            let total = Int64(values.volumeTotalCapacity ?? 0)
            let available = Int64(values.volumeAvailableCapacity ?? 0)

            result.append(VolumeInfo(
                url: url,
                name: name,
                isRemovable: isRemovable,
                isNetwork: isNetwork,
                isEjectable: isEjectable,
                totalCapacity: total,
                availableCapacity: available
            ))
        }

        volumes = result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func startObserving() {
        let nc = NSWorkspace.shared.notificationCenter

        mountObserver = nc.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.loadVolumes()
            }
        }

        unmountObserver = nc.addObserver(
            forName: NSWorkspace.didUnmountNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.loadVolumes()
            }
        }
    }

    func eject(_ volume: VolumeInfo) {
        let name = volume.name
        let path = volume.url.path
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
            process.arguments = ["eject", path]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                await MainActor.run {
                    if process.terminationStatus == 0 {
                        ToastManager.shared.show("Ejected \(name)")
                    } else {
                        ToastManager.shared.show("Eject failed")
                    }
                    self.loadVolumes()
                }
            } catch {
                await MainActor.run {
                    ToastManager.shared.show("Eject failed: \(error.localizedDescription)")
                }
            }
        }
    }
}
