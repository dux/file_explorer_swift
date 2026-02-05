import SwiftUI

struct SearchResult: Identifiable {
    let url: URL
    let isDirectory: Bool
    var id: String { url.absoluteString }
}

struct SearchPane: View {
    @ObservedObject var manager: FileExplorerManager
    @State private var searchQuery: String = ""
    @State private var searchResults: [SearchResult] = []
    @State private var isSearching: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16))
                    .foregroundColor(.blue)
                Text("Search")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button(action: { manager.currentPane = .browser }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Search input
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("Search files...", text: $searchQuery, onCommit: {
                    performSearch()
                })
                .textFieldStyle(.plain)

                if !searchQuery.isEmpty {
                    Button(action: {
                        searchQuery = ""
                        searchResults = []
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

            Divider()

            // Results
            if isSearching {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Searching...")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if searchResults.isEmpty && !searchQuery.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("No results found")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if searchResults.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("Enter a search term")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Text("Search in: \(manager.currentPath.lastPathComponent)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(searchResults) { result in
                            SearchResultRow(url: result.url, isDirectory: result.isDirectory, basePath: manager.currentPath) {
                                manager.navigateTo(result.url.deletingLastPathComponent())
                                manager.selectItem(at: -1, url: result.url)
                                manager.currentPane = .browser
                            }
                        }
                    }
                    .padding(8)
                }
            }
        }
    }

    private func performSearch() {
        guard !searchQuery.isEmpty else { return }

        isSearching = true
        searchResults = []

        let basePath = manager.currentPath
        let query = searchQuery.lowercased()

        DispatchQueue.global(qos: .userInitiated).async {
            var results: [SearchResult] = []

            if let enumerator = FileManager.default.enumerator(
                at: basePath,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) {
                for case let fileURL as URL in enumerator {
                    if fileURL.lastPathComponent.lowercased().contains(query) {
                        let isDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                        results.append(SearchResult(url: fileURL, isDirectory: isDir))
                        if results.count >= 100 { break }
                    }
                }
            }

            DispatchQueue.main.async {
                searchResults = results
                isSearching = false
            }
        }
    }
}

struct SearchResultRow: View {
    let url: URL
    let isDirectory: Bool
    let basePath: URL
    let action: () -> Void

    @State private var isHovered = false

    private var relativePath: String {
        let path = url.path
        let base = basePath.path
        if path.hasPrefix(base) {
            var relative = String(path.dropFirst(base.count))
            if relative.hasPrefix("/") {
                relative = String(relative.dropFirst())
            }
            return relative
        }
        return url.lastPathComponent
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: isDirectory ? "folder.fill" : "doc.fill")
                    .font(.system(size: 14))
                    .foregroundColor(isDirectory ? .blue : .secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(url.lastPathComponent)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Text(relativePath)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.gray.opacity(0.15) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
