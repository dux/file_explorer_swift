import SwiftUI
import AppKit

struct ImageResizeSheet: View {
    let url: URL
    @Binding var isPresented: Bool
    let onComplete: () -> Void

    @State private var originalSize: CGSize = .zero
    @State private var newWidth: String = ""
    @State private var newHeight: String = ""
    @State private var keepAspectRatio = true
    @State private var aspectRatio: CGFloat = 1.0
    @State private var previewImage: NSImage?
    @State private var isProcessing = false
    @State private var errorMessage: String?

    // Crop state
    @State private var isCropMode = false
    @State private var cropStart: CGPoint = .zero
    @State private var cropEnd: CGPoint = .zero
    @State private var isDragging = false
    @State private var imageViewSize: CGSize = .zero
    @State private var containerSize: CGSize = .zero

    enum ResizePreset: String, CaseIterable {
        case half = "50%"
        case quarter = "25%"
        case hd720 = "720p"
        case hd1080 = "1080p"
        case square1024 = "1024²"
        case custom = "Custom"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: isCropMode ? "crop" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 18))
                    .foregroundColor(.pink)
                Text(isCropMode ? "Crop Image" : "Resize Image")
                    .textStyle(.default, weight: .semibold)
                Spacer()

                Picker("", selection: $isCropMode) {
                    Text("Resize").tag(false)
                    Text("Crop").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)

                SheetCloseButton(isPresented: $isPresented)
                    .padding(.leading, 8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Large preview with crop overlay
            ZStack {
                Color.black.opacity(0.05)

                if let image = previewImage {
                    GeometryReader { geo in
                        let imageSize = calculateFitSize(imageSize: originalSize, containerSize: geo.size)
                        let offsetX = (geo.size.width - imageSize.width) / 2
                        let offsetY = (geo.size.height - imageSize.height) / 2

                        ZStack {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: imageSize.width, height: imageSize.height)
                                .position(x: geo.size.width / 2, y: geo.size.height / 2)

                            if isCropMode && isDragging {
                                let rect = normalizedCropRect(in: imageSize, offset: CGPoint(x: offsetX, y: offsetY))

                                Rectangle()
                                    .fill(Color.black.opacity(0.5))
                                    .mask(
                                        Rectangle()
                                            .overlay(
                                                Rectangle()
                                                    .frame(width: rect.width, height: rect.height)
                                                    .position(x: rect.midX, y: rect.midY)
                                                    .blendMode(.destinationOut)
                                            )
                                    )

                                Rectangle()
                                    .stroke(Color.white, lineWidth: 2)
                                    .frame(width: rect.width, height: rect.height)
                                    .position(x: rect.midX, y: rect.midY)

                                ForEach(0..<4, id: \.self) { corner in
                                    let pos = cornerPosition(corner: corner, rect: rect)
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 12, height: 12)
                                        .shadow(radius: 2)
                                        .position(pos)
                                        .gesture(
                                            DragGesture()
                                                .onChanged { value in
                                                    updateCropCorner(corner: corner, location: value.location, imageSize: imageSize, offset: CGPoint(x: offsetX, y: offsetY))
                                                }
                                        )
                                }
                            }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    if isCropMode {
                                        if !isDragging {
                                            cropStart = value.startLocation
                                            isDragging = true
                                        }
                                        cropEnd = value.location
                                        imageViewSize = imageSize
                                    }
                                }
                                .onEnded { _ in }
                        )
                        .onAppear {
                            imageViewSize = imageSize
                            containerSize = geo.size
                        }
                        .onChange(of: geo.size) { newSize in
                            containerSize = newSize
                        }
                    }
                }
            }
            .frame(height: 450)

            Divider()

            // Controls
            VStack(spacing: 12) {
                HStack {
                    Text("Original: \(Int(originalSize.width)) × \(Int(originalSize.height))")
                        .textStyle(.buttons)
                        .foregroundColor(.secondary)
                    Spacer()
                    if !newWidth.isEmpty && !newHeight.isEmpty {
                        Text("New: \(newWidth) × \(newHeight)")
                            .textStyle(.buttons)
                            .foregroundColor(.pink)
                    }
                }

                if isCropMode {
                    if !isDragging {
                        Text("Drag on image to select crop area")
                            .textStyle(.buttons)
                            .foregroundColor(.secondary)
                    } else {
                        HStack {
                            Button("Clear Selection") {
                                isDragging = false
                                cropStart = .zero
                                cropEnd = .zero
                            }
                            .textStyle(.buttons)
                        }
                    }
                } else {
                    // Resize presets
                    HStack(spacing: 6) {
                        ForEach(ResizePreset.allCases.filter { $0 != .custom }, id: \.self) { preset in
                            Button(action: { applyPreset(preset) }) {
                                Text(preset.rawValue)
                                    .textStyle(.buttons)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(Color(NSColor.controlBackgroundColor))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 5)
                                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack(spacing: 8) {
                        TextField("Width", text: $newWidth)
                            .styledInput()
                            .frame(width: 80)
                            .onChange(of: newWidth) { _ in
                                if keepAspectRatio, let w = Double(newWidth) {
                                    newHeight = String(Int(w / aspectRatio))
                                }
                            }

                        Image(systemName: keepAspectRatio ? "link" : "link.badge.plus")
                            .textStyle(.default)
                            .foregroundColor(keepAspectRatio ? .accentColor : .secondary)
                            .onTapGesture { keepAspectRatio.toggle() }

                        TextField("Height", text: $newHeight)
                            .styledInput()
                            .frame(width: 80)
                            .onChange(of: newHeight) { _ in
                                if keepAspectRatio, let h = Double(newHeight) {
                                    newWidth = String(Int(h * aspectRatio))
                                }
                            }

                        Text("px")
                            .textStyle(.buttons)
                            .foregroundColor(.secondary)
                    }
                }

                if let error = errorMessage {
                    Text(error)
                        .textStyle(.buttons)
                        .foregroundColor(.red)
                }
            }
            .padding(12)

            Divider()

            // Footer
            HStack {
                Text(url.lastPathComponent)
                    .textStyle(.buttons)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                Button(action: { isCropMode ? saveCropped() : saveResized() }) {
                    if isProcessing {
                        ProgressView()
                            .scaleEffect(0.6)
                    } else {
                        Text(isCropMode ? "Save Crop" : "Save Resize")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isCropMode ? !isDragging : (newWidth.isEmpty || newHeight.isEmpty) || isProcessing)
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 700, height: 700)
        .onAppear { loadImage() }
    }

    private func calculateFitSize(imageSize: CGSize, containerSize: CGSize) -> CGSize {
        let widthRatio = containerSize.width / imageSize.width
        let heightRatio = containerSize.height / imageSize.height
        let scale = min(widthRatio, heightRatio, 1.0)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    private func normalizedCropRect(in imageSize: CGSize, offset: CGPoint) -> CGRect {
        let minX = min(cropStart.x, cropEnd.x)
        let minY = min(cropStart.y, cropEnd.y)
        let maxX = max(cropStart.x, cropEnd.x)
        let maxY = max(cropStart.y, cropEnd.y)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func cornerPosition(corner: Int, rect: CGRect) -> CGPoint {
        switch corner {
        case 0: return CGPoint(x: rect.minX, y: rect.minY)
        case 1: return CGPoint(x: rect.maxX, y: rect.minY)
        case 2: return CGPoint(x: rect.maxX, y: rect.maxY)
        case 3: return CGPoint(x: rect.minX, y: rect.maxY)
        default: return .zero
        }
    }

    private func updateCropCorner(corner: Int, location: CGPoint, imageSize: CGSize, offset: CGPoint) {
        switch corner {
        case 0:
            cropStart = location
        case 1:
            cropEnd.x = location.x
            cropStart.y = location.y
        case 2:
            cropEnd = location
        case 3:
            cropStart.x = location.x
            cropEnd.y = location.y
        default:
            break
        }
    }

    private func loadImage() {
        guard let image = NSImage(contentsOf: url) else { return }
        previewImage = image

        if let rep = image.representations.first {
            originalSize = CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
            aspectRatio = originalSize.width / originalSize.height
            newWidth = String(Int(originalSize.width))
            newHeight = String(Int(originalSize.height))
        }
    }

    private func applyPreset(_ preset: ResizePreset) {
        switch preset {
        case .half:
            newWidth = String(Int(originalSize.width / 2))
            newHeight = String(Int(originalSize.height / 2))
        case .quarter:
            newWidth = String(Int(originalSize.width / 4))
            newHeight = String(Int(originalSize.height / 4))
        case .hd720:
            if aspectRatio > 1 {
                newWidth = "1280"
                newHeight = String(Int(1280 / aspectRatio))
            } else {
                newHeight = "720"
                newWidth = String(Int(720 * aspectRatio))
            }
        case .hd1080:
            if aspectRatio > 1 {
                newWidth = "1920"
                newHeight = String(Int(1920 / aspectRatio))
            } else {
                newHeight = "1080"
                newWidth = String(Int(1080 * aspectRatio))
            }
        case .square1024:
            newWidth = "1024"
            newHeight = "1024"
            keepAspectRatio = false
        case .custom:
            break
        }
    }

    private func saveCropped() {
        guard isDragging else { return }

        let scale = originalSize.width / imageViewSize.width
        let rect = normalizedCropRect(in: imageViewSize, offset: .zero)

        let imageOffsetX = (containerSize.width - imageViewSize.width) / 2
        let imageOffsetY = (containerSize.height - imageViewSize.height) / 2

        let cropX = max(0, (rect.minX - imageOffsetX) * scale)
        let cropY = max(0, (rect.minY - imageOffsetY) * scale)
        let cropW = min(rect.width * scale, originalSize.width - cropX)
        let cropH = min(rect.height * scale, originalSize.height - cropY)

        guard cropW > 10 && cropH > 10 else {
            errorMessage = "Selection too small"
            return
        }

        isProcessing = true
        errorMessage = nil

        Task {
            let result = await cropImage(x: Int(cropX), y: Int(cropY), width: Int(cropW), height: Int(cropH))
            await MainActor.run {
                isProcessing = false
                if let error = result {
                    errorMessage = error
                } else {
                    onComplete()
                    isPresented = false
                    ToastManager.shared.show("Image cropped")
                }
            }
        }
    }

    nonisolated private func cropImage(x: Int, y: Int, width: Int, height: Int) async -> String? {
        let ext = url.pathExtension.lowercased()
        let baseName = url.deletingPathExtension().lastPathComponent
        let newName = "\(baseName)_cropped.\(ext)"
        let outputURL = url.deletingLastPathComponent().appendingPathComponent(newName)

        do {
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try FileManager.default.removeItem(at: outputURL)
            }
            try FileManager.default.copyItem(at: url, to: outputURL)
        } catch {
            return "Failed to create copy: \(error.localizedDescription)"
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
        process.arguments = [
            "-c", String(height), String(width),
            "--cropOffset", String(y), String(x),
            outputURL.path
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
                let errorStr = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                return "Crop failed: \(errorStr)"
            }
        } catch {
            return "Failed to run sips: \(error.localizedDescription)"
        }

        return nil
    }

    private func saveResized() {
        guard let width = Int(newWidth), let height = Int(newHeight),
              width > 0, height > 0 else {
            errorMessage = "Invalid dimensions"
            return
        }

        isProcessing = true
        errorMessage = nil

        Task {
            let result = await resizeImage(width: width, height: height)
            await MainActor.run {
                isProcessing = false
                if let error = result {
                    errorMessage = error
                } else {
                    onComplete()
                    isPresented = false
                    ToastManager.shared.show("Image resized to \(width)×\(height)")
                }
            }
        }
    }

    nonisolated private func resizeImage(width: Int, height: Int) async -> String? {
        let ext = url.pathExtension.lowercased()
        let baseName = url.deletingPathExtension().lastPathComponent
        let newName = "\(baseName)_\(width)x\(height).\(ext)"
        let outputURL = url.deletingLastPathComponent().appendingPathComponent(newName)

        do {
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try FileManager.default.removeItem(at: outputURL)
            }
            try FileManager.default.copyItem(at: url, to: outputURL)
        } catch {
            return "Failed to create copy: \(error.localizedDescription)"
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
        process.arguments = [
            "-z", String(height), String(width),
            outputURL.path
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
                let errorStr = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                return "Resize failed: \(errorStr)"
            }
        } catch {
            return "Failed to run sips: \(error.localizedDescription)"
        }

        return nil
    }
}
