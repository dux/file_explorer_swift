import Foundation

extension FileExplorerManager {
    // MARK: - Search with fd

    private static func findFd() -> String? {
        for dir in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"] {
            let path = "\(dir)/fd"
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        return nil
    }

    func startSearch() {
        isSearching = true
        searchQuery = ""
        searchResults = []
        listCursorIndex = -1
    }

    func cancelSearch() {
        searchTask?.terminate()
        searchTask = nil
        isSearching = false
        searchQuery = ""
        searchResults = []
        isSearchRunning = false
        listCursorIndex = -1
    }

    // MARK: - List cursor navigation (search results / color tags)

    func listSelectNext(count: Int) {
        guard count > 0 else { return }
        if listCursorIndex < count - 1 {
            listCursorIndex += 1
        } else {
            listCursorIndex = 0
        }
    }

    func listSelectPrevious(count: Int) {
        guard count > 0 else { return }
        if listCursorIndex > 0 {
            listCursorIndex -= 1
        } else {
            listCursorIndex = count - 1
        }
    }

    func listActivateItem(url: URL, isDirectory: Bool) {
        if isDirectory {
            if isSearching { cancelSearch() }
            currentPane = .browser
            navigateTo(url)
        } else {
            openFileWithPreferredApp(url)
        }
    }

    func performSearch(_ query: String) {
        searchQuery = query

        searchDebounceTask?.cancel()
        searchTask?.terminate()
        searchTask = nil

        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            searchResults = []
            isSearchRunning = false
            return
        }

        guard let fdPath = Self.findFd() else {
            ToastManager.shared.show("fd not found — install with: brew install fd")
            return
        }

        isSearchRunning = true

        searchDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            self.executeSearch(query: query, trimmed: trimmed, fdPath: fdPath)
        }
    }

    private func executeSearch(query: String, trimmed: String, fdPath: String) {
        let searchDir = currentPath.path
        let showAll = showHidden

        let process = Process()
        process.executableURL = URL(fileURLWithPath: fdPath)
        var args = ["--max-results", "200", "--color", "never"]
        if showAll {
            args += ["--hidden", "--no-ignore"]
        }
        args += [trimmed, searchDir]
        process.arguments = args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        self.searchTask = process

        Task.detached {
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                guard process.terminationStatus == 0 || process.terminationStatus == 1,
                      let output = String(data: data, encoding: .utf8) else {
                    await MainActor.run { [weak self] in
                        self?.searchResults = []
                        self?.isSearchRunning = false
                    }
                    return
                }

                let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey, .isHiddenKey]
                let results: [CachedFileInfo] = output.split(separator: "\n").compactMap { line in
                    let path = String(line)
                    guard !path.isEmpty else { return nil }
                    let url = URL(fileURLWithPath: path)
                    let values = try? url.resourceValues(forKeys: resourceKeys)
                    let isDir = values?.isDirectory ?? false
                    let size = Int64(values?.fileSize ?? 0)
                    let modDate = values?.contentModificationDate
                    let hidden = url.lastPathComponent.hasPrefix(".") || (values?.isHidden ?? false)
                    return CachedFileInfo(url: url, isDirectory: isDir, size: size, modDate: modDate, isHidden: hidden)
                }

                let sorted = results.sorted { a, b in
                    if a.isDirectory != b.isDirectory { return a.isDirectory }
                    return a.name.localizedStandardCompare(b.name) == .orderedAscending
                }

                await MainActor.run { [weak self] in
                    if self?.searchQuery == query {
                        self?.searchResults = sorted
                        self?.isSearchRunning = false
                    }
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.searchResults = []
                    self?.isSearchRunning = false
                }
            }
        }
    }
}
