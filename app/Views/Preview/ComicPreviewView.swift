import SwiftUI
import AppKit

struct ComicPreviewView: View {
    let url: URL
    @State private var pages: [URL] = []
    @State private var totalPages: Int = 0
    @State private var isLoading = true
    @State private var error: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            PreviewHeader(title: "Comic preview", icon: "book.fill", color: .purple)
            Divider()

            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Extracting pages...")
                        .textStyle(.buttons)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text(error)
                        .textStyle(.buttons)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geometry in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            if totalPages > pages.count {
                                Text("\(totalPages) pages")
                                    .textStyle(.small)
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 4)
                            }
                            ForEach(Array(pages.enumerated()), id: \.offset) { _, pageURL in
                                ComicPageView(url: pageURL, width: geometry.size.width)
                            }
                        }
                    }
                }
            }
        }
        .task(id: url) {
            await extractPages()
        }
    }

    private func extractPages() async {
        isLoading = true
        error = nil
        pages = []

        let archiveURL = url
        let result = await Task.detached(priority: .userInitiated) {
            ComicExtractor.extract(from: archiveURL)
        }.value

        switch result {
        case .success(let (urls, total)):
            pages = urls
            totalPages = total
        case .failure(let err):
            error = err.localizedDescription
        }
        isLoading = false
    }
}

struct ComicPageView: View {
    let url: URL
    let width: CGFloat
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                let aspect = image.size.height / max(image.size.width, 1)
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: width, height: width * aspect)
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: width, height: width * 1.4)
            }
        }
        .task(id: url) {
            image = nil
            let pageURL = url
            let data = await Task.detached(priority: .userInitiated) {
                try? Data(contentsOf: pageURL)
            }.value
            if let data {
                image = NSImage(data: data)
            }
        }
    }
}

enum ComicExtractor {
    private static let imageExtensions = FileExtensions.comicImages

    static func extract(from url: URL) -> Result<([URL], Int), Error> {
        let ext = url.pathExtension.lowercased()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ComicPreview")
            .appendingPathComponent(UUID().uuidString)

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            return .failure(error)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.currentDirectoryURL = tempDir

        if ext == "cbr" {
            process.arguments = ["unrar", "e", "-o+", url.path]
        } else {
            process.arguments = ["unzip", "-j", "-o", url.path]
        }

        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return .failure(error)
        }

        guard let contents = try? FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil) else {
            return .success(([], 0))
        }

        let imageURLs = contents.filter {
            imageExtensions.contains($0.pathExtension.lowercased())
        }.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }

        return .success((imageURLs, imageURLs.count))
    }
}
