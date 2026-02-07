import SwiftUI

struct ColorTagView: View {
    let color: TagColor
    @ObservedObject var manager: FileExplorerManager
    @ObservedObject var tagManager = ColorTagManager.shared

    private var files: [TaggedFile] {
        tagManager.list(color)
    }

    var body: some View {
        let _ = tagManager.version
        let fileCount = tagManager.count(for: color)
        VStack(spacing: 0) {
            // Header bar
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(color.color)
                    .frame(width: 16, height: 16)

                Text(color.label)
                    .font(.system(size: 14, weight: .semibold))

                Text("\(fileCount) item\(fileCount == 1 ? "" : "s")")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: {
                    manager.currentPane = .browser
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Back to browser")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(color.color.opacity(0.12))

            Divider()

            if files.isEmpty {
                VStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(color.color.opacity(0.15))
                        .frame(width: 48, height: 48)
                        .overlay(
                            Image(systemName: "tag")
                                .font(.system(size: 22))
                                .foregroundColor(color.color)
                        )
                    Text("No items tagged \(color.label.lowercased())")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Text("Right-click any file and choose Color Label")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(files) { file in
                            ColorTagFileRow(
                                file: file,
                                color: color,
                                manager: manager,
                                tagManager: tagManager
                            )
                        }
                    }
                }
            }
        }
        .background(Color(NSColor.textBackgroundColor))
    }
}

struct ColorTagFileRow: View {
    let file: TaggedFile
    let color: TagColor
    @ObservedObject var manager: FileExplorerManager
    @ObservedObject var tagManager: ColorTagManager
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            if file.exists {
                if file.isDirectory {
                    FolderIconView(url: file.url, size: 22)
                } else {
                    Image(nsImage: IconProvider.shared.icon(for: file.url, isDirectory: false))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 22, height: 22)
                }
            } else {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 18))
                    .foregroundColor(.secondary.opacity(0.5))
                    .frame(width: 22, height: 22)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(file.name)
                    .font(.system(size: 14, weight: file.exists ? .regular : .regular))
                    .foregroundColor(file.exists ? .primary : .secondary.opacity(0.5))
                    .strikethrough(!file.exists)
                    .lineLimit(1)

                Text(file.parentPath)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if isHovered {
                Button(action: {
                    tagManager.untagFile(file.url, color: color)
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove tag")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(isHovered ? Color.gray.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            guard file.exists else { return }
            // Navigate to file's parent and select it
            manager.currentPane = .browser
            let parent = file.url.deletingLastPathComponent()
            manager.navigateTo(parent)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                if let index = manager.allItems.firstIndex(where: { $0.url == file.url }) {
                    manager.selectItem(at: index, url: file.url)
                }
            }
        }
    }
}

// MARK: - Reusable inline color tag items for context menu

struct ColorTagMenuItems: View {
    let url: URL
    @ObservedObject var tagManager: ColorTagManager

    var body: some View {
        ForEach(TagColor.allCases) { color in
            Button(action: { tagManager.toggleTag(url, color: color) }) {
                Label {
                    Text(color.label)
                } icon: {
                    Image(systemName: tagManager.isTagged(url, color: color) ? "checkmark.circle.fill" : "circle.fill")
                        .foregroundColor(color.color)
                }
            }
        }

        let currentColors = tagManager.colorsForFile(url)
        if !currentColors.isEmpty {
            Button(action: { tagManager.untagFile(url) }) {
                Label("Remove All Labels", systemImage: "xmark.circle")
            }
        }
    }
}
