import SwiftUI
import AppKit

struct FolderGalleryPreview: View {
    let folderURL: URL
    @State private var imageURLs: [URL] = []
    @State private var totalCount: Int = 0

    nonisolated private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "bmp", "webp", "heic", "heif", "tiff", "tif", "svg", "avif"]

    var body: some View {
        VStack(spacing: 0) {
            PreviewHeader(title: "\(totalCount) images", icon: "photo.on.rectangle", color: .purple)
            Divider()

            GeometryReader { geometry in
                let spacing: CGFloat = 4
                let boxSize = (geometry.size.width - spacing) / 2
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.fixed(boxSize), spacing: spacing),
                        GridItem(.fixed(boxSize), spacing: spacing)
                    ], spacing: spacing) {
                        ForEach(imageURLs, id: \.self) { url in
                            FolderGalleryThumbnail(url: url, size: boxSize, isSelected: false)
                        }
                    }
                }
            }
        }
        .task(id: folderURL) {
            let dir = folderURL
            let result = await Task.detached(priority: .userInitiated) {
                let fm = FileManager.default
                guard let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return ([URL](), 0) }
                let images = contents.filter { Self.imageExtensions.contains($0.pathExtension.lowercased()) }
                    .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
                return (Array(images.prefix(10)), images.count)
            }.value
            imageURLs = result.0
            totalCount = result.1
        }
    }
}

struct FolderGalleryThumbnail: View {
    let url: URL
    let size: CGFloat
    let isSelected: Bool

    var body: some View {
        if let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipped()
                .overlay(
                    Rectangle()
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
                )
        }
    }
}
