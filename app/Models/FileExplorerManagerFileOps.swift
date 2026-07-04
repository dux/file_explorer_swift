import Foundation
import AppKit

extension FileExplorerManager {
    func promptForNewFolder(in target: URL? = nil) {
        newFolderTargetURL = target
        newFolderName = "New Folder"
        showNewFolderDialog = true
    }

    func promptForNewFile(in target: URL? = nil) {
        newFileTargetURL = target
        newFileName = "untitled.txt"
        showNewFileDialog = true
    }

    func createNewFolder(named name: String? = nil) {
        let destination = newFolderTargetURL ?? currentPath
        newFolderTargetURL = nil
        var folderName = name ?? "New Folder"
        var counter = 1
        var newFolderURL = destination.appendingPathComponent(folderName)

        // Find unique name if exists
        while fileManager.fileExists(atPath: newFolderURL.path) {
            folderName = "\(name ?? "New Folder") \(counter)"
            newFolderURL = destination.appendingPathComponent(folderName)
            counter += 1
        }

        do {
            try fileManager.createDirectory(at: newFolderURL, withIntermediateDirectories: false)
            loadContents { [weak self] in
                guard let self else { return }
                // Select the new folder only if it lives in the current path
                if destination.path == self.currentPath.path {
                    self.selectedItem = newFolderURL
                    if let index = self.allItems.firstIndex(where: { $0.url == newFolderURL }) {
                        self.selectedIndex = index
                    }
                }
            }
        } catch {
            ToastManager.shared.showError("Error creating folder: \(error.localizedDescription)")
        }
    }

    func createNewFile(named name: String? = nil) {
        let destination = newFileTargetURL ?? currentPath
        newFileTargetURL = nil
        var fileName = name ?? "untitled.txt"
        var counter = 1
        var newFileURL = destination.appendingPathComponent(fileName)

        // Find unique name if exists
        let baseName = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        while fileManager.fileExists(atPath: newFileURL.path) {
            fileName = ext.isEmpty ? "\(baseName) \(counter)" : "\(baseName) \(counter).\(ext)"
            newFileURL = destination.appendingPathComponent(fileName)
            counter += 1
        }

        do {
            try "".write(to: newFileURL, atomically: true, encoding: .utf8)
            loadContents { [weak self] in
                guard let self else { return }
                if destination.path == self.currentPath.path {
                    self.selectedItem = newFileURL
                    if let index = self.allItems.firstIndex(where: { $0.url == newFileURL }) {
                        self.selectedIndex = index
                    }
                }
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

        let dst = newURL
        Task {
            guard await backgroundCopy(from: url, to: dst) else { return }
            // Select the duplicate once the refreshed listing is in
            loadContents { [weak self] in
                guard let self else { return }
                self.selectedItem = dst
                if let index = self.allItems.firstIndex(where: { $0.url == dst }) {
                    self.selectedIndex = index
                }
            }
        }
    }

    /// Faithfully copies `src` to `dst` off the main thread, showing the running
    /// indicator. Cleans up a partial copy on cancel; reports errors via toast.
    /// Returns true on success.
    func backgroundCopy(from src: URL, to dst: URL) async -> Bool {
        await OperationManager.shared.run(title: "Duplicating") { () -> Bool in
            do {
                try copyItemFiltered(at: src, to: dst, skipping: [])
                return true
            } catch is CancellationError {
                try? FileManager.default.removeItem(at: dst)
                return false
            } catch {
                let msg = error.localizedDescription
                Task { @MainActor in ToastManager.shared.showError("Error duplicating file: \(msg)") }
                return false
            }
        }
    }

    func promptDuplicate(_ url: URL) {
        let baseName = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        duplicateText = ext.isEmpty ? "\(baseName) copy" : "\(baseName) copy.\(ext)"
        duplicatingItem = url
    }

    func cancelDuplicate() {
        duplicatingItem = nil
        duplicateText = ""
    }

    func confirmDuplicate() {
        guard let source = duplicatingItem else {
            cancelDuplicate()
            return
        }
        let newName = duplicateText.trimmingCharacters(in: .whitespaces)
        guard !newName.isEmpty, newName != source.lastPathComponent else {
            cancelDuplicate()
            return
        }
        let dst = source.deletingLastPathComponent().appendingPathComponent(newName)
        cancelDuplicate()
        Task {
            guard await backgroundCopy(from: source, to: dst) else { return }
            loadContents { [weak self] in
                guard let self else { return }
                self.selectedItem = dst
                if let index = self.allItems.firstIndex(where: { $0.url == dst }) {
                    self.selectedIndex = index
                }
            }
        }
    }

    func addToZip(_ url: URL) {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        let isDirectory = values?.isDirectory == true
        let baseName = isDirectory ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
        var zipName = "\(baseName).zip"
        var counter = 1
        let parentURL = url.deletingLastPathComponent()
        let itemName = url.lastPathComponent
        var zipURL = parentURL.appendingPathComponent(zipName)

        // Find unique name
        while fileManager.fileExists(atPath: zipURL.path) {
            zipName = "\(baseName) \(counter).zip"
            zipURL = url.deletingLastPathComponent().appendingPathComponent(zipName)
            counter += 1
        }

        let finalZipName = zipName
        let finalZipURL = zipURL
        let skipFolders = Self.defaultZipSkipFolders.union(AppSettings.shared.copySkipFolders)
        let excludePatterns = Self.zipExcludePatterns(for: itemName, skipFolders: skipFolders)

        ToastManager.shared.show("Creating zip...")

        Task.detached {
            let process = Process()
            let outputPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            process.currentDirectoryURL = parentURL
            var arguments = [
                "-r",
                finalZipURL.path,
                itemName,
                "-x",
                "__MACOSX/*",
                "*/.DS_Store",
                "*/._*"
            ]
            arguments.append(contentsOf: excludePatterns)
            process.arguments = arguments
            process.standardOutput = outputPipe
            process.standardError = outputPipe

            do {
                try process.run()
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                let status = process.terminationStatus
                await MainActor.run {
                    if status == 0 {
                        self.loadContents { [weak self] in
                            guard let self else { return }
                            self.selectedItem = finalZipURL
                            if let index = self.allItems.firstIndex(where: { $0.url == finalZipURL }) {
                                self.selectedIndex = index
                            }
                        }
                        ToastManager.shared.show("Created \(finalZipName)")
                    } else {
                        let output = String(data: outputData, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if let output, !output.isEmpty {
                            ToastManager.shared.showError(output)
                        } else {
                            ToastManager.shared.showError("Error creating zip")
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    ToastManager.shared.show("Error creating zip: \(error.localizedDescription)")
                }
            }
        }
    }

    nonisolated private static let defaultZipSkipFolders: Set<String> = [
        ".git", ".hg", ".idea", ".svn", ".vscode",
        "build", "coverage"
    ]

    nonisolated private static func zipExcludePatterns(for itemName: String, skipFolders: Set<String>) -> [String] {
        skipFolders.flatMap { folder in
            [
                "\(itemName)/\(folder)",
                "\(itemName)/\(folder)/*",
                "\(itemName)/*/\(folder)",
                "\(itemName)/*/\(folder)/*"
            ]
        }
    }

    func runApp(_ url: URL) {
        guard url.pathExtension.lowercased() == "app" else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            Task { @MainActor in
                if let error {
                    ToastManager.shared.showError("Failed to launch app: \(error.localizedDescription)")
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
        // Check if we're deleting the current directory or an ancestor of it
        let isCurrentOrAncestor = currentPath.path == url.path ||
            currentPath.path.hasPrefix(url.path + "/")

        Task {
            let ok = await OperationManager.shared.run(title: "Moving to Trash") { () -> Bool in
                do {
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                    return true
                } catch {
                    let msg = error.localizedDescription
                    Task { @MainActor in ToastManager.shared.showError("Error moving to trash: \(msg)") }
                    return false
                }
            }
            guard ok else { return }

            // Remove from selection if it was selected
            SelectionManager.shared.removeByPath(url.path)

            if isCurrentOrAncestor {
                // Navigate to the parent of the deleted folder and focus it
                let parent = url.deletingLastPathComponent()
                navigateToFolder(parent)
            } else {
                loadContents()
            }
            ToastManager.shared.show("Moved to Trash")
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
            // Select the renamed item once the refreshed listing is in
            loadContents { [weak self] in
                guard let self else { return }
                self.selectedItem = newURL
                if let index = self.allItems.firstIndex(where: { $0.url == newURL }) {
                    self.selectedIndex = index
                }
            }
        } catch {
            ToastManager.shared.showError("Error renaming: \(error.localizedDescription)")
            cancelRename()
        }
    }

    func toggleHidden(_ url: URL) {
        do {
            let resourceValues = try url.resourceValues(forKeys: [.isHiddenKey])
            let isCurrentlyHidden = resourceValues.isHidden ?? url.lastPathComponent.hasPrefix(".")
            var newValues = URLResourceValues()
            newValues.isHidden = !isCurrentlyHidden
            var mutableURL = url
            try mutableURL.setResourceValues(newValues)
            loadContents { [weak self] in
                guard let self else { return }
                self.selectedItem = url
                if let index = self.allItems.firstIndex(where: { $0.url == url }) {
                    self.selectedIndex = index
                }
            }
            ToastManager.shared.show(isCurrentlyHidden ? "Made visible" : "Made hidden")
        } catch {
            ToastManager.shared.showError("Error toggling hidden: \(error.localizedDescription)")
        }
    }
}
