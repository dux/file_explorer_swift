import Foundation

@MainActor
class FZFSearch: ObservableObject {
    @Published var searchText: String = ""
    @Published var results: [(url: URL, relativePath: String, isDirectory: Bool)] = []
    @Published var isSearching: Bool = false
    @Published var selectedIndex: Int = -1

    private var basePath: URL?
    private var currentTask: Task<Void, Never>?

    var selectedURL: URL? {
        guard selectedIndex >= 0 && selectedIndex < results.count else { return nil }
        return results[selectedIndex].url
    }

    func start(from path: URL) {
        basePath = path
        isSearching = true
        searchText = ""
        results = []
        selectedIndex = -1
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        isSearching = false
        searchText = ""
        results = []
        selectedIndex = -1
        basePath = nil
    }

    func appendChar(_ char: String) {
        searchText += char
        performSearch()
    }

    func backspace() {
        if searchText.isEmpty {
            cancel()
        } else {
            searchText.removeLast()
            if searchText.isEmpty {
                results = []
                selectedIndex = -1
            } else {
                performSearch()
            }
        }
    }

    func selectNext() {
        guard !results.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % results.count
    }

    func selectPrevious() {
        guard !results.isEmpty else { return }
        selectedIndex = selectedIndex > 0 ? selectedIndex - 1 : results.count - 1
    }

    private func performSearch() {
        currentTask?.cancel()

        guard !searchText.isEmpty, let basePath = basePath else {
            results = []
            return
        }

        let query = searchText
        let searchPath = basePath

        // Get fzf path - try bundle first, then homebrew
        let bundleFzfPath = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/fzf").path
        let fzfPath = FileManager.default.fileExists(atPath: bundleFzfPath)
            ? bundleFzfPath
            : "/opt/homebrew/bin/fzf"

        // Escape query for shell
        let escapedQuery = query
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "`", with: "\\`")

        // Escape path for shell
        let escapedPath = searchPath.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
            cd "\(escapedPath)" && \
            find . -not -path '*/.*' -maxdepth 10 2>/dev/null | \
            "\(fzfPath)" --filter "\(escapedQuery)" 2>/dev/null | \
            head -10
            """

        currentTask = Task {
            let searchResults = await runFzfSearch(script: script, searchPath: searchPath)

            if !Task.isCancelled {
                self.results = searchResults
                if !searchResults.isEmpty {
                    self.selectedIndex = 0
                }
            }
        }
    }

    nonisolated private func runFzfSearch(script: String, searchPath: URL) async -> [(url: URL, relativePath: String, isDirectory: Bool)] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", script]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            let output = String(data: data, encoding: .utf8) ?? ""

            return output
                .split(separator: "\n")
                .prefix(10)
                .compactMap { line in
                    let relativePath = String(line)
                        .trimmingCharacters(in: .whitespaces)
                        .replacingOccurrences(of: "./", with: "")
                    guard !relativePath.isEmpty else { return nil }
                    let url = searchPath.appendingPathComponent(relativePath)
                    var isDir: ObjCBool = false
                    FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                    return (url: url, relativePath: relativePath, isDirectory: isDir.boolValue)
                }
        } catch {
            return []
        }
    }
}
