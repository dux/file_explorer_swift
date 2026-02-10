import Foundation
import Combine
import CiMobileDevice

struct iPhoneDevice: Identifiable, Equatable {
    let id: String  // UDID
    let name: String
    var isConnected: Bool = true
}

struct iPhoneApp: Identifiable, Equatable {
    let id: String  // Bundle ID
    let name: String
    let version: String
}

struct iPhoneFile: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let path: String
    let isDirectory: Bool
    let size: Int64
    let modifiedDate: Date?

    func hash(into hasher: inout Hasher) {
        hasher.combine(path)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.path == rhs.path
    }
}

/// Represents a selected iPhone file with its context
struct iPhoneSelection: Hashable {
    let deviceId: String
    let appId: String
    let appName: String
    let file: iPhoneFile
}

enum iPhoneBrowseMode: Equatable {
    case apps  // Show list of apps
    case appDocuments(appId: String, appName: String)  // Browsing app's Documents
}

@MainActor
class iPhoneManager: ObservableObject {
    static let shared = iPhoneManager()

    @Published var devices: [iPhoneDevice] = []
    @Published var isScanning: Bool = false
    @Published var lastError: String?
    @Published var currentDevice: iPhoneDevice?
    @Published var browseMode: iPhoneBrowseMode = .apps
    @Published var currentPath: String = "/"
    @Published var apps: [iPhoneApp] = []
    @Published var files: [iPhoneFile] = []
    @Published var isLoadingFiles: Bool = false
    @Published var selectedFile: iPhoneFile?

    private var scanTimer: Timer?
    internal let fileManager = FileManager.default
    internal let cacheDir: URL

    private init() {
        let tmpDir = fileManager.temporaryDirectory
        cacheDir = tmpDir.appendingPathComponent("dux-file-explorer-iphone-cache")
        try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        startPeriodicScan()
    }

    func cleanup() {
        scanTimer?.invalidate()
        scanTimer = nil
    }

    // MARK: - Device Detection

    func startPeriodicScan() {
        Task { await scanForDevices() }
        scanTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.scanForDevices()
            }
        }
    }

    func stopPeriodicScan() {
        scanTimer?.invalidate()
        scanTimer = nil
    }

    func scanForDevices() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        let foundDevices = await Task.detached { () -> [(String, String)] in
            var deviceList: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
            var count: Int32 = 0

            let err = idevice_get_device_list(&deviceList, &count)
            guard err == IDEVICE_E_SUCCESS, let list = deviceList else {
                return []
            }

            var results: [(String, String)] = []
            for i in 0..<Int(count) {
                if let udidPtr = list[i] {
                    let udid = String(cString: udidPtr)
                    let name = self.getDeviceNameSync(udid: udid)
                    results.append((udid, name))
                }
            }

            idevice_device_list_free(deviceList)
            return results
        }.value

        var newDevices: [iPhoneDevice] = []
        for (udid, name) in foundDevices {
            newDevices.append(iPhoneDevice(id: udid, name: name, isConnected: true))
        }

        // Clear current device if disconnected
        if let current = currentDevice, !foundDevices.contains(where: { $0.0 == current.id }) {
            currentDevice = nil
            apps = []
            files = []
            browseMode = .apps
            currentPath = "/"
        }

        devices = newDevices
        lastError = nil
    }

    nonisolated private func getDeviceNameSync(udid: String) -> String {
        var device: idevice_t?
        var lockdown: lockdownd_client_t?

        guard idevice_new(&device, udid) == IDEVICE_E_SUCCESS, let dev = device else {
            return "iPhone (\(udid.prefix(8))...)"
        }
        defer { idevice_free(dev) }

        guard lockdownd_client_new_with_handshake(dev, &lockdown, "FileExplorer") == LOCKDOWN_E_SUCCESS,
              let client = lockdown else {
            return "iPhone (\(udid.prefix(8))...)"
        }
        defer { lockdownd_client_free(client) }

        var namePtr: UnsafeMutablePointer<CChar>?
        if lockdownd_get_device_name(client, &namePtr) == LOCKDOWN_E_SUCCESS, let ptr = namePtr {
            let name = String(cString: ptr)
            free(ptr)
            return name
        }

        return "iPhone (\(udid.prefix(8))...)"
    }

    // MARK: - Device Selection & App Loading

    func selectDevice(_ device: iPhoneDevice) async {
        currentDevice = device
        browseMode = .apps
        currentPath = "/"
        files = []
        await loadApps()
    }

    func loadApps() async {
        guard let device = currentDevice else { return }
        isLoadingFiles = true
        defer { isLoadingFiles = false }

        let udid = device.id
        let loadedApps = await Task.detached { () -> [iPhoneApp] in
            var idev: idevice_t?
            var lockdown: lockdownd_client_t?
            var service: lockdownd_service_descriptor_t?
            var instproxy: instproxy_client_t?

            guard idevice_new(&idev, udid) == IDEVICE_E_SUCCESS, let dev = idev else { return [] }
            defer { idevice_free(dev) }

            guard lockdownd_client_new_with_handshake(dev, &lockdown, "FileExplorer") == LOCKDOWN_E_SUCCESS,
                  let lock = lockdown else { return [] }
            defer { lockdownd_client_free(lock) }

            guard lockdownd_start_service(lock, "com.apple.mobile.installation_proxy", &service) == LOCKDOWN_E_SUCCESS,
                  let svc = service else { return [] }
            defer { lockdownd_service_descriptor_free(svc) }

            guard instproxy_client_new(dev, svc, &instproxy) == INSTPROXY_E_SUCCESS,
                  let client = instproxy else { return [] }
            defer { instproxy_client_free(client) }

            // Create options to get user apps with file sharing
            let options = plist_new_dict()
            defer { plist_free(options) }
            plist_dict_set_item(options, "ApplicationType", plist_new_string("User"))

            var result: plist_t?
            guard instproxy_browse(client, options, &result) == INSTPROXY_E_SUCCESS,
                  let appList = result else { return [] }
            defer { plist_free(appList) }

            var apps: [iPhoneApp] = []
            let count = plist_array_get_size(appList)

            for i in 0..<count {
                guard let appInfo = plist_array_get_item(appList, i) else { continue }

                // Check if app has file sharing enabled
                guard let fileSharingNode = plist_dict_get_item(appInfo, "UIFileSharingEnabled") else { continue }

                // Handle different plist types for the boolean value
                let nodeType = plist_get_node_type(fileSharingNode)
                var hasFileSharing = false

                if nodeType == PLIST_BOOLEAN {
                    var boolVal: UInt8 = 0
                    plist_get_bool_val(fileSharingNode, &boolVal)
                    hasFileSharing = boolVal != 0
                } else if nodeType == PLIST_STRING {
                    var strPtr: UnsafeMutablePointer<CChar>?
                    plist_get_string_val(fileSharingNode, &strPtr)
                    if let ptr = strPtr {
                        let str = String(cString: ptr).lowercased()
                        hasFileSharing = (str == "true" || str == "yes" || str == "1")
                        free(ptr)
                    }
                } else if nodeType == PLIST_INT {
                    var intVal: Int64 = 0
                    plist_get_int_val(fileSharingNode, &intVal)
                    hasFileSharing = intVal != 0
                }

                if !hasFileSharing { continue }

                // Get bundle ID
                guard let bundleIdNode = plist_dict_get_item(appInfo, "CFBundleIdentifier") else { continue }
                var bundleIdPtr: UnsafeMutablePointer<CChar>?
                plist_get_string_val(bundleIdNode, &bundleIdPtr)
                guard let bidPtr = bundleIdPtr else { continue }
                let bundleId = String(cString: bidPtr)
                free(bidPtr)

                // Get display name
                var displayName = bundleId
                if let nameNode = plist_dict_get_item(appInfo, "CFBundleDisplayName") {
                    var namePtr: UnsafeMutablePointer<CChar>?
                    plist_get_string_val(nameNode, &namePtr)
                    if let ptr = namePtr {
                        displayName = String(cString: ptr)
                        free(ptr)
                    }
                } else if let nameNode = plist_dict_get_item(appInfo, "CFBundleName") {
                    var namePtr: UnsafeMutablePointer<CChar>?
                    plist_get_string_val(nameNode, &namePtr)
                    if let ptr = namePtr {
                        displayName = String(cString: ptr)
                        free(ptr)
                    }
                }

                // Get version
                var version = ""
                if let versionNode = plist_dict_get_item(appInfo, "CFBundleShortVersionString") {
                    var versionPtr: UnsafeMutablePointer<CChar>?
                    plist_get_string_val(versionNode, &versionPtr)
                    if let ptr = versionPtr {
                        version = String(cString: ptr)
                        free(ptr)
                    }
                }

                apps.append(iPhoneApp(id: bundleId, name: displayName, version: version))
            }

            return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }.value

        apps = loadedApps
    }

    // MARK: - App Documents Browsing

    // Base path for app documents (VendDocuments gives us /Documents access)
    private let appDocumentsBasePath = "/Documents"

    func selectApp(_ app: iPhoneApp) async {
        browseMode = .appDocuments(appId: app.id, appName: app.name)
        currentPath = appDocumentsBasePath
        await loadFiles()
    }

    func backToApps() {
        browseMode = .apps
        currentPath = "/"
        files = []
    }

    func navigateTo(_ path: String) async {
        currentPath = path
        await loadFiles()
    }

    func navigateUp() async {
        // If at base path, go back to apps
        guard currentPath != appDocumentsBasePath else {
            backToApps()
            return
        }
        let parent = (currentPath as NSString).deletingLastPathComponent
        currentPath = parent.isEmpty || parent == "/" ? appDocumentsBasePath : parent
        await loadFiles()
    }

    func loadFiles() async {
        guard let device = currentDevice,
              case .appDocuments(let appId, _) = browseMode else { return }
        isLoadingFiles = true
        defer { isLoadingFiles = false }

        let path = currentPath
        let udid = device.id

        let loadedFiles = await Task.detached { () -> [iPhoneFile] in
            var idev: idevice_t?
            var lockdown: lockdownd_client_t?
            var service: lockdownd_service_descriptor_t?
            var houseArrest: house_arrest_client_t?
            var afc: afc_client_t?

            guard idevice_new(&idev, udid) == IDEVICE_E_SUCCESS, let dev = idev else { return [] }
            defer { idevice_free(dev) }

            guard lockdownd_client_new_with_handshake(dev, &lockdown, "FileExplorer") == LOCKDOWN_E_SUCCESS,
                  let lock = lockdown else { return [] }
            defer { lockdownd_client_free(lock) }

            guard lockdownd_start_service(lock, HOUSE_ARREST_SERVICE_NAME, &service) == LOCKDOWN_E_SUCCESS,
                  let svc = service else { return [] }
            defer { lockdownd_service_descriptor_free(svc) }

            guard house_arrest_client_new(dev, svc, &houseArrest) == HOUSE_ARREST_E_SUCCESS,
                  let haClient = houseArrest else { return [] }
            defer { house_arrest_client_free(haClient) }

            // Request access to app's Documents
            guard house_arrest_send_command(haClient, "VendDocuments", appId) == HOUSE_ARREST_E_SUCCESS else { return [] }

            // Check result
            var resultPlist: plist_t?
            guard house_arrest_get_result(haClient, &resultPlist) == HOUSE_ARREST_E_SUCCESS else { return [] }
            if let result = resultPlist {
                // Check for error
                if let errorNode = plist_dict_get_item(result, "Error") {
                    var errorPtr: UnsafeMutablePointer<CChar>?
                    plist_get_string_val(errorNode, &errorPtr)
                    if let ptr = errorPtr {
                        print("House arrest error: \(String(cString: ptr))")
                        free(ptr)
                    }
                    plist_free(result)
                    return []
                }
                plist_free(result)
            }

            // Create AFC client from house arrest
            guard afc_client_new_from_house_arrest_client(haClient, &afc) == AFC_E_SUCCESS,
                  let afcClient = afc else { return [] }
            // Note: Don't free afc separately, house_arrest_client_free handles it

            // Read directory
            var dirInfo: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
            guard afc_read_directory(afcClient, path, &dirInfo) == AFC_E_SUCCESS, let entries = dirInfo else {
                return []
            }
            defer { afc_dictionary_free(dirInfo) }

            var results: [iPhoneFile] = []
            var i = 0
            while let entryPtr = entries[i] {
                let name = String(cString: entryPtr)
                i += 1

                if name == "." || name == ".." { continue }

                let fullPath = path == "/" ? "/\(name)" : "\(path)/\(name)"

                // Get file info
                var fileInfo: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
                var isDir = false
                var size: Int64 = 0
                var modDate: Date?

                if afc_get_file_info(afcClient, fullPath, &fileInfo) == AFC_E_SUCCESS, let info = fileInfo {
                    var j = 0
                    while let keyPtr = info[j], let valPtr = info[j + 1] {
                        let key = String(cString: keyPtr)
                        let val = String(cString: valPtr)

                        switch key {
                        case "st_ifmt":
                            isDir = (val == "S_IFDIR")
                        case "st_size":
                            size = Int64(val) ?? 0
                        case "st_mtime":
                            if let ts = Double(val) {
                                modDate = Date(timeIntervalSince1970: ts / 1_000_000_000)
                            }
                        default:
                            break
                        }
                        j += 2
                    }
                    afc_dictionary_free(fileInfo)
                }

                results.append(iPhoneFile(
                    name: name,
                    path: fullPath,
                    isDirectory: isDir,
                    size: size,
                    modifiedDate: modDate
                ))
            }

            return results.sorted { a, b in
                if a.isDirectory != b.isDirectory { return a.isDirectory }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        }.value

        files = loadedFiles
    }

    // MARK: - Selection Management

    func isSelected(_ file: iPhoneFile) -> Bool {
        guard let device = currentDevice,
              case .appDocuments(let appId, _) = browseMode else { return false }

        return SelectionManager.shared.containsIPhone(path: file.path, deviceId: device.id, appId: appId)
    }

    // File operations in iPhoneManagerFileOps.swift
}
