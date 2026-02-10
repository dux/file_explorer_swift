import Foundation
import CiMobileDevice

extension iPhoneManager {
    // MARK: - AFC Client Helper

    /// Sets up an AFC client connection to an app's documents via house_arrest, calls the body closure, and cleans up.
    nonisolated static func withAfcClient<T>(deviceId: String, appId: String, body: (afc_client_t) -> T?) -> T? {
        var idev: idevice_t?
        var lockdown: lockdownd_client_t?
        var service: lockdownd_service_descriptor_t?
        var houseArrest: house_arrest_client_t?
        var afc: afc_client_t?

        guard idevice_new(&idev, deviceId) == IDEVICE_E_SUCCESS, let dev = idev else { return nil }
        defer { idevice_free(dev) }

        guard lockdownd_client_new_with_handshake(dev, &lockdown, "FileExplorer") == LOCKDOWN_E_SUCCESS,
              let lock = lockdown else { return nil }
        defer { lockdownd_client_free(lock) }

        guard lockdownd_start_service(lock, HOUSE_ARREST_SERVICE_NAME, &service) == LOCKDOWN_E_SUCCESS,
              let svc = service else { return nil }
        defer { lockdownd_service_descriptor_free(svc) }

        guard house_arrest_client_new(dev, svc, &houseArrest) == HOUSE_ARREST_E_SUCCESS,
              let haClient = houseArrest else { return nil }
        defer { house_arrest_client_free(haClient) }

        guard house_arrest_send_command(haClient, "VendDocuments", appId) == HOUSE_ARREST_E_SUCCESS else { return nil }

        var resultPlist: plist_t?
        guard house_arrest_get_result(haClient, &resultPlist) == HOUSE_ARREST_E_SUCCESS else { return nil }
        if let result = resultPlist { plist_free(result) }

        guard afc_client_new_from_house_arrest_client(haClient, &afc) == AFC_E_SUCCESS,
              let afcClient = afc else { return nil }

        return body(afcClient)
    }

    // MARK: - Download file from iPhone

    func downloadFile(_ file: iPhoneFile) async -> URL? {
        guard let device = currentDevice,
              case .appDocuments(let appId, _) = browseMode,
              !file.isDirectory else { return nil }

        let localPath = cacheDir.appendingPathComponent(file.name)
        try? fileManager.removeItem(at: localPath)

        let udid = device.id
        let remotePath = file.path

        let success = await Task.detached { () -> Bool in
            Self.withAfcClient(deviceId: udid, appId: appId) { afcClient in
                var handle: UInt64 = 0
                guard afc_file_open(afcClient, remotePath, AFC_FOPEN_RDONLY, &handle) == AFC_E_SUCCESS else { return false }
                defer { afc_file_close(afcClient, handle) }

                guard let outputStream = OutputStream(url: localPath, append: false) else { return false }
                outputStream.open()
                defer { outputStream.close() }

                var buffer = [UInt8](repeating: 0, count: 65536)
                var bytesRead: UInt32 = 0

                while true {
                    let err = afc_file_read(afcClient, handle, &buffer, UInt32(buffer.count), &bytesRead)
                    if err != AFC_E_SUCCESS || bytesRead == 0 { break }
                    outputStream.write(buffer, maxLength: Int(bytesRead))
                }

                return true
            } ?? false
        }.value

        return success ? localPath : nil
    }

    // MARK: - Delete file on iPhone

    func deleteFile(_ file: iPhoneFile) async -> Bool {
        guard let device = currentDevice,
              case .appDocuments(let appId, _) = browseMode else { return false }

        let udid = device.id
        let remotePath = file.path
        let isDirectory = file.isDirectory

        return await Task.detached { () -> Bool in
            Self.withAfcClient(deviceId: udid, appId: appId) { afcClient in
                if isDirectory {
                    return Self.deleteDirectoryRecursive(afcClient, path: remotePath)
                } else {
                    return afc_remove_path(afcClient, remotePath) == AFC_E_SUCCESS
                }
            } ?? false
        }.value
    }

    // MARK: - Upload files from Mac to iPhone

    func uploadFiles(_ localURLs: [URL]) async -> Int {
        guard let device = currentDevice,
              case .appDocuments(let appId, _) = browseMode else { return 0 }

        var uploadedCount = 0
        let udid = device.id
        let targetPath = currentPath
        let fm = FileManager.default

        for localURL in localURLs {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: localURL.path, isDirectory: &isDir) else { continue }

            let remotePath = targetPath == "/" ? "/\(localURL.lastPathComponent)" : "\(targetPath)/\(localURL.lastPathComponent)"

            let success = await Task.detached { () -> Bool in
                Self.withAfcClient(deviceId: udid, appId: appId) { afcClient in
                    if isDir.boolValue {
                        return Self.uploadDirectoryRecursive(afcClient, localPath: localURL, remotePath: remotePath)
                    } else {
                        return Self.uploadSingleFile(afcClient, localURL: localURL, remotePath: remotePath)
                    }
                } ?? false
            }.value

            if success {
                uploadedCount += 1
            }
        }

        // Refresh file list after upload
        if uploadedCount > 0 {
            await loadFiles()
        }

        return uploadedCount
    }

    // MARK: - Context-based operations (for SelectionManager)

    /// Download file with explicit context (device/app)
    func downloadFileFromContext(deviceId: String, appId: String, remotePath: String, to localPath: URL) async -> Bool {
        try? fileManager.removeItem(at: localPath)

        return await Task.detached { () -> Bool in
            Self.withAfcClient(deviceId: deviceId, appId: appId) { afcClient in
                var handle: UInt64 = 0
                guard afc_file_open(afcClient, remotePath, AFC_FOPEN_RDONLY, &handle) == AFC_E_SUCCESS else { return false }
                defer { afc_file_close(afcClient, handle) }

                guard let outputStream = OutputStream(url: localPath, append: false) else { return false }
                outputStream.open()
                defer { outputStream.close() }

                var buffer = [UInt8](repeating: 0, count: 65536)
                var bytesRead: UInt32 = 0

                while true {
                    let err = afc_file_read(afcClient, handle, &buffer, UInt32(buffer.count), &bytesRead)
                    if err != AFC_E_SUCCESS || bytesRead == 0 { break }
                    outputStream.write(buffer, maxLength: Int(bytesRead))
                }

                return true
            } ?? false
        }.value
    }

    /// Upload file or directory with explicit context
    func uploadFileFromContext(deviceId: String, appId: String, localURL: URL, toPath: String) async -> Bool {
        let remotePath = toPath.hasSuffix("/") ? "\(toPath)\(localURL.lastPathComponent)" : "\(toPath)/\(localURL.lastPathComponent)"

        // Check if it's a directory
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: localURL.path, isDirectory: &isDir) else { return false }

        return await Task.detached { () -> Bool in
            Self.withAfcClient(deviceId: deviceId, appId: appId) { afcClient in
                if isDir.boolValue {
                    return Self.uploadDirectoryRecursive(afcClient, localPath: localURL, remotePath: remotePath)
                } else {
                    return Self.uploadSingleFile(afcClient, localURL: localURL, remotePath: remotePath)
                }
            } ?? false
        }.value
    }

    /// Delete file with explicit context
    func deleteFileFromContext(deviceId: String, appId: String, remotePath: String) async -> Bool {
        return await Task.detached { () -> Bool in
            Self.withAfcClient(deviceId: deviceId, appId: appId) { afcClient in
                afc_remove_path(afcClient, remotePath) == AFC_E_SUCCESS
            } ?? false
        }.value
    }

    // MARK: - Static helper functions for recursive operations

    nonisolated static func uploadSingleFile(_ afc: afc_client_t, localURL: URL, remotePath: String) -> Bool {
        var handle: UInt64 = 0
        guard afc_file_open(afc, remotePath, AFC_FOPEN_WRONLY, &handle) == AFC_E_SUCCESS else { return false }
        defer { afc_file_close(afc, handle) }

        guard let inputStream = InputStream(url: localURL) else { return false }
        inputStream.open()
        defer { inputStream.close() }

        var buffer = [UInt8](repeating: 0, count: 65536)

        while inputStream.hasBytesAvailable {
            let bytesRead = inputStream.read(&buffer, maxLength: buffer.count)
            if bytesRead <= 0 { break }

            var bytesWritten: UInt32 = 0
            let err = afc_file_write(afc, handle, buffer, UInt32(bytesRead), &bytesWritten)
            if err != AFC_E_SUCCESS { return false }
        }

        return true
    }

    nonisolated static func uploadDirectoryRecursive(_ afc: afc_client_t, localPath: URL, remotePath: String) -> Bool {
        // Create remote directory
        if afc_make_directory(afc, remotePath) != AFC_E_SUCCESS {
            // Directory might already exist, continue anyway
        }

        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: localPath, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return false
        }

        for item in contents {
            let itemRemotePath = "\(remotePath)/\(item.lastPathComponent)"
            var isDir: ObjCBool = false
            fm.fileExists(atPath: item.path, isDirectory: &isDir)

            if isDir.boolValue {
                if !uploadDirectoryRecursive(afc, localPath: item, remotePath: itemRemotePath) {
                    return false
                }
            } else {
                if !uploadSingleFile(afc, localURL: item, remotePath: itemRemotePath) {
                    return false
                }
            }
        }

        return true
    }

    nonisolated static func deleteDirectoryRecursive(_ afc: afc_client_t, path: String) -> Bool {
        var entries: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
        guard afc_read_directory(afc, path, &entries) == AFC_E_SUCCESS, let entryList = entries else {
            return false
        }
        defer { afc_dictionary_free(entryList) }

        var i = 0
        while let entry = entryList[i] {
            let name = String(cString: entry)
            i += 1
            if name == "." || name == ".." { continue }

            let fullPath = path == "/" ? "/\(name)" : "\(path)/\(name)"

            // Check if it's a directory
            var info: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
            if afc_get_file_info(afc, fullPath, &info) == AFC_E_SUCCESS, let infoList = info {
                var isDir = false
                var j = 0
                while let key = infoList[j], let value = infoList[j + 1] {
                    if String(cString: key) == "st_ifmt" && String(cString: value) == "S_IFDIR" {
                        isDir = true
                    }
                    j += 2
                }
                afc_dictionary_free(infoList)

                if isDir {
                    if !deleteDirectoryRecursive(afc, path: fullPath) {
                        return false
                    }
                } else {
                    if afc_remove_path(afc, fullPath) != AFC_E_SUCCESS {
                        return false
                    }
                }
            }
        }

        // Now remove the empty directory
        return afc_remove_path(afc, path) == AFC_E_SUCCESS
    }
}
