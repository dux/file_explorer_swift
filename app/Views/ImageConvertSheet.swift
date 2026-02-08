import SwiftUI
import AppKit
import ImageIO

struct ImageConvertSheet: View {
    let url: URL
    @Binding var isPresented: Bool
    let onComplete: () -> Void

    enum ImageFormat: String, CaseIterable, Identifiable {
        case png = "PNG"
        case jpeg = "JPEG"
        case heic = "HEIC"
        case tiff = "TIFF"
        case bmp = "BMP"
        case gif = "GIF"
        case webp = "WebP"

        var id: String { rawValue }

        var fileExtension: String {
            switch self {
            case .png: return "png"
            case .jpeg: return "jpg"
            case .heic: return "heic"
            case .tiff: return "tiff"
            case .bmp: return "bmp"
            case .gif: return "gif"
            case .webp: return "webp"
            }
        }

        var supportsQuality: Bool {
            switch self {
            case .jpeg, .heic, .webp: return true
            default: return false
            }
        }

        var supportsAlpha: Bool {
            switch self {
            case .png, .tiff, .gif, .webp: return true
            default: return false
            }
        }

        var utType: CFString {
            switch self {
            case .png: return "public.png" as CFString
            case .jpeg: return "public.jpeg" as CFString
            case .heic: return "public.heic" as CFString
            case .tiff: return "public.tiff" as CFString
            case .bmp: return "com.microsoft.bmp" as CFString
            case .gif: return "com.compuserve.gif" as CFString
            case .webp: return "public.webp" as CFString
            }
        }
    }

    @State private var selectedFormat: ImageFormat = .png
    @State private var quality: Double = 0.85
    @State private var preserveAlpha = true
    @State private var isProcessing = false
    @State private var resultMessage: String?
    @State private var originalSize: CGSize = .zero
    @State private var originalFileSize: String = ""
    @State private var previewImage: NSImage?

    private var sourceExtension: String {
        url.pathExtension.lowercased()
    }

    private var availableFormats: [ImageFormat] {
        ImageFormat.allCases.filter { $0.fileExtension != sourceExtension && $0.fileExtension != altExtension }
    }

    private var altExtension: String {
        if sourceExtension == "jpg" { return "jpeg" }
        if sourceExtension == "jpeg" { return "jpg" }
        if sourceExtension == "tif" { return "tiff" }
        if sourceExtension == "tiff" { return "tif" }
        return ""
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(icon: "arrow.triangle.2.circlepath", title: "Convert Image", color: .cyan, isPresented: $isPresented)
            Divider()

            // Preview
            if let image = previewImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 180)
                    .padding(12)
                    .background(Color.black.opacity(0.03))
            }

            Divider()

            // Source info
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Source")
                        .textStyle(.title)
                    Spacer()
                }

                HStack(spacing: 12) {
                    Label(sourceExtension.uppercased(), systemImage: "doc.fill")
                        .textStyle(.buttons)
                    Text("\(Int(originalSize.width)) x \(Int(originalSize.height))")
                        .textStyle(.buttons)
                        .foregroundColor(.secondary)
                    Text(originalFileSize)
                        .textStyle(.buttons)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            // Format selection
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Convert to")
                        .textStyle(.title)
                    Spacer()
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(availableFormats) { format in
                        Button(action: { selectedFormat = format }) {
                            Text(format.rawValue)
                                .textStyle(.buttons, weight: selectedFormat == format ? .semibold : .regular)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(selectedFormat == format ? Color.accentColor : Color.gray.opacity(0.12))
                                )
                                .foregroundColor(selectedFormat == format ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if selectedFormat.supportsQuality {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Quality")
                                .textStyle(.buttons)
                            Spacer()
                            Text("\(Int(quality * 100))%")
                                .textStyle(.buttons)
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $quality, in: 0.1...1.0, step: 0.05)
                        HStack {
                            Text("Smaller file")
                                .textStyle(.small)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("Better quality")
                                .textStyle(.small)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                if selectedFormat.supportsAlpha {
                    Toggle("Preserve transparency", isOn: $preserveAlpha)
                        .textStyle(.buttons)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Spacer()

            Divider()

            // Result message
            if let msg = resultMessage {
                HStack {
                    Image(systemName: msg.contains("Error") ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundColor(msg.contains("Error") ? .red : .green)
                    Text(msg)
                        .textStyle(.small)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }

            // Actions
            HStack {
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(action: convertImage) {
                    if isProcessing {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Text("Convert to \(selectedFormat.rawValue)")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing)
                .keyboardShortcut(.defaultAction)
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 420, height: 560)
        .onAppear {
            loadImageInfo()
            if let first = availableFormats.first {
                selectedFormat = first
            }
        }
    }

    private func loadImageInfo() {
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? UInt64 {
            originalFileSize = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
        }

        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else { return }

        originalSize = CGSize(width: cgImage.width, height: cgImage.height)
        previewImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    private func convertImage() {
        isProcessing = true
        resultMessage = nil

        Task.detached(priority: .userInitiated) {
            do {
                guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                    throw ConvertError.loadFailed
                }

                let format = await selectedFormat
                let qual = await quality
                let keepAlpha = await preserveAlpha

                let dir = url.deletingLastPathComponent()
                let baseName = url.deletingPathExtension().lastPathComponent
                var outputURL = dir.appendingPathComponent("\(baseName).\(format.fileExtension)")

                var counter = 1
                while FileManager.default.fileExists(atPath: outputURL.path) {
                    outputURL = dir.appendingPathComponent("\(baseName)-\(counter).\(format.fileExtension)")
                    counter += 1
                }

                guard let destination = CGImageDestinationCreateWithURL(
                    outputURL as CFURL,
                    format.utType,
                    1,
                    nil
                ) else {
                    throw ConvertError.createDestFailed
                }

                var options: [CFString: Any] = [:]

                if format.supportsQuality {
                    options[kCGImageDestinationLossyCompressionQuality] = qual
                }

                var finalImage = cgImage
                if !format.supportsAlpha || !keepAlpha {
                    if cgImage.alphaInfo != .none && cgImage.alphaInfo != .noneSkipLast && cgImage.alphaInfo != .noneSkipFirst {
                        if let flattened = flattenAlpha(cgImage) {
                            finalImage = flattened
                        }
                    }
                }

                CGImageDestinationAddImage(destination, finalImage, options as CFDictionary)

                guard CGImageDestinationFinalize(destination) else {
                    throw ConvertError.writeFailed
                }

                let outAttrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
                let outSize = outAttrs[.size] as? UInt64 ?? 0
                let outSizeStr = ByteCountFormatter.string(fromByteCount: Int64(outSize), countStyle: .file)

                await MainActor.run {
                    resultMessage = "Saved \(outputURL.lastPathComponent) (\(outSizeStr))"
                    isProcessing = false
                    onComplete()
                }
            } catch {
                await MainActor.run {
                    resultMessage = "Error: \(error.localizedDescription)"
                    isProcessing = false
                }
            }
        }
    }

    nonisolated private func flattenAlpha(_ image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }

        context.setFillColor(CGColor.white)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        return context.makeImage()
    }

    enum ConvertError: LocalizedError {
        case loadFailed
        case createDestFailed
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .loadFailed: return "Failed to load image"
            case .createDestFailed: return "Failed to create output file"
            case .writeFailed: return "Failed to write converted image"
            }
        }
    }
}
