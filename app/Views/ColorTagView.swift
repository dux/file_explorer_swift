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
                        ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                            ColorTagFileRow(
                                file: file,
                                index: index,
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
    let index: Int
    let color: TagColor
    @ObservedObject var manager: FileExplorerManager
    @ObservedObject var tagManager: ColorTagManager

    var body: some View {
        FileListRow(
            url: file.url,
            isDirectory: file.isDirectory,
            exists: file.exists,
            parentPath: file.parentPath,
            isSelected: manager.selectedItem == file.url,
            showRemove: true,
            onRemove: { tagManager.untagFile(file.url, color: color) }
        )
        .onTapGesture {
            guard file.exists else { return }
            manager.listCursorIndex = index
            manager.selectItem(at: -1, url: file.url)
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
