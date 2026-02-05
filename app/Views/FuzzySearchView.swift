import SwiftUI

struct FuzzySearchView: View {
    @ObservedObject var fzfSearch: FZFSearch
    let onOpenFolder: (URL) -> Void
    @State private var alertPath: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Search input bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.accentColor)

                Text(fzfSearch.searchText.isEmpty ? "Type to search..." : fzfSearch.searchText)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(fzfSearch.searchText.isEmpty ? .secondary : .primary)

                Spacer()

                Button(action: { fzfSearch.cancel() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Results list
            if fzfSearch.results.isEmpty && !fzfSearch.searchText.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("No matches")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(fzfSearch.results.enumerated()), id: \.element.url) { index, result in
                                FuzzyResultRow(
                                    relativePath: result.relativePath,
                                    url: result.url,
                                    isDirectory: result.isDirectory,
                                    isSelected: fzfSearch.selectedIndex == index,
                                    onTap: { handleTap(result) }
                                )
                                .id(index)
                            }
                        }
                    }
                    .onChange(of: fzfSearch.selectedIndex) { newIndex in
                        if newIndex >= 0 {
                            withAnimation(.easeInOut(duration: 0.1)) {
                                proxy.scrollTo(newIndex, anchor: .center)
                            }
                        }
                    }
                }
            }

            Divider()

            // Keyboard hints
            HStack(spacing: 16) {
                Label("Navigate", systemImage: "arrow.up.arrow.down")
                Label("Open", systemImage: "return")
                Label("Cancel", systemImage: "escape")
            }
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .padding(8)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.2), radius: 20)
        .padding(20)
        .alert("File Path", isPresented: .init(
            get: { alertPath != nil },
            set: { if !$0 { alertPath = nil } }
        )) {
            Button("OK") { alertPath = nil }
        } message: {
            Text(alertPath ?? "")
        }
    }

    private func handleTap(_ result: (url: URL, relativePath: String, isDirectory: Bool)) {
        if result.isDirectory {
            fzfSearch.cancel()
            onOpenFolder(result.url)
        } else {
            alertPath = result.url.path
        }
    }
}

struct FuzzyResultRow: View {
    let relativePath: String
    let url: URL
    let isDirectory: Bool
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isDirectory ? "folder.fill" : "doc.fill")
                .foregroundColor(isDirectory ? Color(red: 0.35, green: 0.67, blue: 0.95) : .secondary)
                .frame(width: 20)

            Text(relativePath)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(isSelected ? .white : .primary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}
