import Foundation

extension FileExplorerManager {
    func createNewFolder(named name: String? = nil) {
        var folderName = name ?? "New Folder"
        var counter = 1
        var newFolderURL = currentPath.appendingPathComponent(folderName)

        // Find unique name if exists
        while fileManager.fileExists(atPath: newFolderURL.path) {
            folderName = "\(name ?? "New Folder") \(counter)"
            newFolderURL = currentPath.appendingPathComponent(folderName)
            counter += 1
        }

        do {
            try fileManager.createDirectory(at: newFolderURL, withIntermediateDirectories: false)
            loadContents()
            // Select the new folder
            selectedItem = newFolderURL
            if let index = allItems.firstIndex(where: { $0.url == newFolderURL }) {
                selectedIndex = index
            }
        } catch {
            ToastManager.shared.showError("Error creating folder: \(error.localizedDescription)")
        }
    }

    func createNewFile() {
        var fileName = "untitled.txt"
        var counter = 1
        var newFileURL = currentPath.appendingPathComponent(fileName)

        // Find unique name
        while fileManager.fileExists(atPath: newFileURL.path) {
            fileName = "untitled \(counter).txt"
            newFileURL = currentPath.appendingPathComponent(fileName)
            counter += 1
        }

        do {
            try "".write(to: newFileURL, atomically: true, encoding: .utf8)
            loadContents()
            // Select and start rename after UI updates
            selectedItem = newFileURL
            if let index = allItems.firstIndex(where: { $0.url == newFileURL }) {
                selectedIndex = index
            }
            // Delay rename to ensure UI has updated
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [self] in
                startRename()
            }
        } catch {
            ToastManager.shared.showError("Error creating file: \(error.localizedDescription)")
        }
    }

    func duplicateFile(_ url: URL) {
        let baseName = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var newName = ext.isEmpty ? "\(baseName) copy" : "\(baseName) copy.\(ext)"
        var counter = 2
        var newURL = url.deletingLastPathComponent().appendingPathComponent(newName)

        // Find unique name
        while fileManager.fileExists(atPath: newURL.path) {
            newName = ext.isEmpty ? "\(baseName) copy \(counter)" : "\(baseName) copy \(counter).\(ext)"
            newURL = url.deletingLastPathComponent().appendingPathComponent(newName)
            counter += 1
        }

        do {
            try fileManager.copyItem(at: url, to: newURL)
            loadContents()
            // Select the duplicate
            selectedItem = newURL
            if let index = allItems.firstIndex(where: { $0.url == newURL }) {
                selectedIndex = index
            }
        } catch {
            ToastManager.shared.showError("Error duplicating file: \(error.localizedDescription)")
        }
    }

    func addToZip(_ url: URL) {
        let baseName = url.deletingPathExtension().lastPathComponent
        var zipName = "\(baseName).zip"
        var counter = 1
        var zipURL = url.deletingLastPathComponent().appendingPathComponent(zipName)

        // Find unique name
        while fileManager.fileExists(atPath: zipURL.path) {
            zipName = "\(baseName) \(counter).zip"
            zipURL = url.deletingLastPathComponent().appendingPathComponent(zipName)
            counter += 1
        }

        let finalZipName = zipName
        let finalZipURL = zipURL
        let srcPath = url.path

        ToastManager.shared.show("Creating zip...")

        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", srcPath, finalZipURL.path]

            do {
                try process.run()
                process.waitUntilExit()

                let status = process.terminationStatus
                await MainActor.run {
                    if status == 0 {
                        self.loadContents()
                        self.selectedItem = finalZipURL
                        if let index = self.allItems.firstIndex(where: { $0.url == finalZipURL }) {
                            self.selectedIndex = index
                        }
                        ToastManager.shared.show("Created \(finalZipName)")
                    } else {
                        ToastManager.shared.show("Error creating zip")
                    }
                }
            } catch {
                await MainActor.run {
                    ToastManager.shared.show("Error creating zip: \(error.localizedDescription)")
                }
            }
        }
    }

    func enableUnsafeApp(_ url: URL) {
        guard url.pathExtension.lowercased() == "app" else { return }
        let appPath = url.path
        ToastManager.shared.show("Enabling \(url.deletingPathExtension().lastPathComponent)...")
        Task.detached {
            // Remove quarantine attributes
            let xattr = Process()
            xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            xattr.arguments = ["-cr", appPath]
            try? xattr.run()
            xattr.waitUntilExit()
            // Remove ._ files
            let findDot = Process()
            findDot.executableURL = URL(fileURLWithPath: "/usr/bin/find")
            findDot.arguments = [appPath, "-name", "._*", "-delete"]
            try? findDot.run()
            findDot.waitUntilExit()
            // Remove .DS_Store files
            let findDS = Process()
            findDS.executableURL = URL(fileURLWithPath: "/usr/bin/find")
            findDS.arguments = [appPath, "-name", ".DS_Store", "-delete"]
            try? findDS.run()
            findDS.waitUntilExit()
            // Re-sign the app
            let codesign = Process()
            codesign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            codesign.arguments = ["--force", "--deep", "--sign", "-", appPath]
            try? codesign.run()
            codesign.waitUntilExit()
            let success = codesign.terminationStatus == 0
            await MainActor.run {
                if success {
                    ToastManager.shared.show("App enabled successfully")
                } else {
                    ToastManager.shared.showError("Failed to enable app")
                }
            }
        }
    }

    func moveToTrash(_ url: URL) {
        do {
            try fileManager.trashItem(at: url, resultingItemURL: nil)
            // Remove from selection if it was selected
            SelectionManager.shared.removeByPath(url.path)
            loadContents()
            ToastManager.shared.show("Moved to Trash")
        } catch {
            ToastManager.shared.showError("Error moving to trash: \(error.localizedDescription)")
        }
    }

    func refresh() {
        loadContents()
    }

    func clearSelection() {
        selectedIndex = -1
        selectedItem = nil
    }

    func selectCurrentFolder() {
        selectedIndex = -1
        selectedItem = currentPath
    }

    func startRename() {
        guard let item = selectedItem else { return }
        renamingItem = item
        renameText = item.lastPathComponent
    }

    func cancelRename() {
        renamingItem = nil
        renameText = ""
    }

    func confirmRename() {
        guard let item = renamingItem, !renameText.isEmpty else {
            cancelRename()
            return
        }

        let newURL = item.deletingLastPathComponent().appendingPathComponent(renameText)

        // Don't rename if name hasn't changed
        if newURL.path == item.path {
            cancelRename()
            return
        }

        do {
            try fileManager.moveItem(at: item, to: newURL)
            // Update path in selection if it was selected
            SelectionManager.shared.updateLocalPath(from: item.path, to: newURL.path)
            cancelRename()
            loadContents()
            // Select the renamed item
            selectedItem = newURL
            if let index = allItems.firstIndex(where: { $0.url == newURL }) {
                selectedIndex = index
            }
        } catch {
            ToastManager.shared.showError("Error renaming: \(error.localizedDescription)")
            cancelRename()
        }
    }

    func toggleHidden(_ url: URL) {
        let fileName = url.lastPathComponent
        let isHidden = fileName.hasPrefix(".")
        
        var newName: String
        if isHidden {
            // Make visible: remove the leading "."
            newName = String(fileName.dropFirst())
        } else {
            // Make hidden: add a leading "."
            newName = ".\(fileName)"
        }
        
        let newURL = url.deletingLastPathComponent().appendingPathComponent(newName)
        
        do {
            try fileManager.moveItem(at: url, to: newURL)
            // Update path in selection if it was selected
            SelectionManager.shared.updateLocalPath(from: url.path, to: newURL.path)
            loadContents()
            // Select the renamed item
            selectedItem = newURL
            if let index = allItems.firstIndex(where: { $0.url == newURL }) {
                selectedIndex = index
            }
            ToastManager.shared.show(isHidden ? "Made visible" : "Made hidden")
        } catch {
            ToastManager.shared.showError("Error toggling hidden: \(error.localizedDescription)")
        }
    }
}
