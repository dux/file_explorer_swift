import SwiftUI
import AppKit
import ImageIO

struct FolderGalleryPreview: View {
    let folderURL: URL
    @State private var imageURLs: [URL] = []
    @State private var totalCount: Int = 0

    nonisolated private static let imageExtensions = FileExtensions.images

    var body: some View {
        VStack(spacing: 0) {
            PreviewHeader(title: "\(totalCount) images", icon: "photo.on.rectangle", color: .purple)
            Divider()

            GeometryReader { geometry in
                let spacing: CGFloat = 3
                let columns = 3
                let boxSize = (geometry.size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(boxSize), spacing: spacing), count: columns), spacing: spacing) {
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
                return (Array(images.prefix(9)), images.count)
            }.value
            imageURLs = result.0
            totalCount = result.1
        }
    }
}

/// Shared, memory-pressure-evicting cache of downsampled gallery thumbnails.
final class ThumbnailCache: @unchecked Sendable {
    static let shared = ThumbnailCache()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 512
    }

    func image(for key: NSString) -> NSImage? { cache.object(forKey: key) }
    func store(_ image: NSImage, for key: NSString) { cache.setObject(image, forKey: key) }

    /// Decodes a downsampled thumbnail via ImageIO (decodes at target size, not full resolution).
    /// Returns PNG data so the result can cross the concurrency boundary; nil for formats ImageIO
    /// can't rasterize (e.g. SVG), which the caller loads directly instead.
    nonisolated static func thumbnailData(url: URL, maxPixel: CGFloat) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
    }
}

struct FolderGalleryThumbnail: View {
    let url: URL
    let size: CGFloat
    let isSelected: Bool

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.12))
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .overlay(
            Rectangle()
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
        )
        .task(id: url) {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        // Decode at box size * screen scale so thumbnails stay crisp on Retina.
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let maxPixel = size * scale
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate?.timeIntervalSince1970 ?? 0
        let key = "\(url.path)|\(Int(maxPixel))|\(mtime)" as NSString

        if let cached = ThumbnailCache.shared.image(for: key) {
            image = cached
            return
        }

        let target = url
        let px = maxPixel
        let data = await Task.detached(priority: .userInitiated) {
            ThumbnailCache.thumbnailData(url: target, maxPixel: px)
        }.value

        let result: NSImage?
        if let data, let decoded = NSImage(data: data) {
            result = decoded
        } else {
            // ImageIO couldn't rasterize (e.g. SVG); load it directly.
            result = NSImage(contentsOf: target)
        }

        guard let result else { return }
        ThumbnailCache.shared.store(result, for: key)
        image = result
    }
}
