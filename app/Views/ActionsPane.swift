import SwiftUI
import AppKit
import ImageIO

// Cache for apps per file extension
@MainActor
final class OpenWithCache {
    static let shared = OpenWithCache()
    private var cache: [String: [(url: URL, name: String, icon: NSImage)]] = [:]

    private init() {}

    func getApps(for ext: String) -> [(url: URL, name: String, icon: NSImage)]? {
        return cache[ext]
    }

    func setApps(_ apps: [(url: URL, name: String, icon: NSImage)], for ext: String) {
        cache[ext] = apps
    }
}

struct ActionsPane: View {
    @ObservedObject var manager: FileExplorerManager
    @ObservedObject var settings = AppSettings.shared
    @State private var allApps: [(url: URL, name: String, icon: NSImage)] = []
    @State private var showAppSelector = false
    @State private var showExifSheet = false
    @State private var showOfficeMetadataSheet = false
    @State private var showImageResizeSheet = false

    // Use selected file if any, otherwise current folder
    private var targetURL: URL {
        manager.selectedItem ?? manager.currentPath
    }

    private var isDirectory: Bool {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: targetURL.path, isDirectory: &isDir)
        return isDir.boolValue
    }

    private var targetName: String {
        targetURL.lastPathComponent
    }

    private var fileType: String {
        if isDirectory {
            return "__folder__"
        }
        let ext = targetURL.pathExtension.lowercased()
        return ext.isEmpty ? "__empty__" : ext
    }

    private var isImageFile: Bool {
        let imageExtensions = ["jpg", "jpeg", "png", "heic", "heif", "tiff", "tif", "gif", "bmp", "webp"]
        return imageExtensions.contains(targetURL.pathExtension.lowercased())
    }

    private var isOfficeFile: Bool {
        let officeExtensions = ["docx", "xlsx", "pptx", "doc", "xls", "ppt"]
        return officeExtensions.contains(targetURL.pathExtension.lowercased())
    }

    private var preferredAppPaths: [String] {
        settings.getPreferredApps(for: fileType)
    }

    private var preferredApps: [(url: URL, name: String, icon: NSImage)] {
        preferredAppPaths.compactMap { path -> (url: URL, name: String, icon: NSImage)? in
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            let name = url.deletingPathExtension().lastPathComponent
            let icon = NSWorkspace.shared.icon(forFile: path)
            return (url: url, name: name, icon: icon)
        }
    }

    private var otherApps: [(url: URL, name: String, icon: NSImage)] {
        let preferredSet = Set(preferredAppPaths)
        return allApps.filter { !preferredSet.contains($0.url.path) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // File/Folder Options section
            VStack(alignment: .leading, spacing: 2) {
                Text(isDirectory ? "Folder options" : "File options")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)

                Text(targetName)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            VStack(spacing: 2) {
                ActionButton(
                    icon: "checkmark.circle",
                    title: "Add to selection",
                    color: .green
                ) {
                    manager.addFileToSelection(targetURL)
                }

                ActionButton(
                    icon: "doc.on.doc",
                    title: "Copy path",
                    color: .blue
                ) {
                    copyPath()
                }

                ActionButton(
                    icon: "pencil",
                    title: "Rename",
                    color: .orange
                ) {
                    manager.startRename()
                }

                // EXIF for images
                if isImageFile {
                    ActionButton(
                        icon: "camera.aperture",
                        title: "EXIF / Metadata",
                        color: .teal
                    ) {
                        showExifSheet = true
                    }

                    ActionButton(
                        icon: "arrow.up.left.and.arrow.down.right",
                        title: "Resize / Crop",
                        color: .pink
                    ) {
                        showImageResizeSheet = true
                    }
                }

                // Office metadata
                if isOfficeFile {
                    ActionButton(
                        icon: "doc.text.magnifyingglass",
                        title: "Document Info",
                        color: .indigo
                    ) {
                        showOfficeMetadataSheet = true
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Open with")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .padding(.horizontal, 10)
                        .padding(.top, 8)
                        .padding(.bottom, 4)

                    // Select app option (first item)
                    ActionButton(
                        icon: "app.badge",
                        title: "Select app...",
                        color: .purple
                    ) {
                        showAppSelector = true
                    }

                    // Preferred apps section
                    if !preferredApps.isEmpty {
                        ForEach(preferredApps, id: \.url.path) { app in
                            PreferredAppButton(
                                icon: app.icon,
                                title: app.name,
                                onOpen: {
                                    NSWorkspace.shared.open([targetURL], withApplicationAt: app.url, configuration: NSWorkspace.OpenConfiguration())
                                },
                                onRemove: {
                                    settings.removePreferredApp(for: fileType, appPath: app.url.path)
                                }
                            )
                        }

                        Text("Other apps")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                            .padding(.horizontal, 10)
                            .padding(.top, 12)
                            .padding(.bottom, 4)
                    }

                    // Other apps
                    ForEach(otherApps, id: \.url.path) { app in
                        ActionButtonWithIcon(
                            icon: app.icon,
                            title: app.name
                        ) {
                            // Add to preferred when clicked
                            settings.addPreferredApp(for: fileType, appPath: app.url.path)
                            NSWorkspace.shared.open([targetURL], withApplicationAt: app.url, configuration: NSWorkspace.OpenConfiguration())
                        }
                    }

                    if allApps.isEmpty {
                        Text("No apps available")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .padding(.vertical, 20)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .onChange(of: targetURL) { newURL in
            loadApps(for: newURL)
        }
        .onAppear {
            loadApps(for: targetURL)
        }
        .sheet(isPresented: $showAppSelector) {
            AppSelectorSheet(
                targetURL: targetURL,
                fileType: fileType,
                settings: settings,
                isPresented: $showAppSelector
            )
        }
        .sheet(isPresented: $showExifSheet) {
            ExifMetadataSheet(url: targetURL, isPresented: $showExifSheet)
        }
        .sheet(isPresented: $showOfficeMetadataSheet) {
            OfficeMetadataSheet(url: targetURL, isPresented: $showOfficeMetadataSheet)
        }
        .sheet(isPresented: $showImageResizeSheet) {
            ImageResizeSheet(url: targetURL, isPresented: $showImageResizeSheet) {
                manager.refresh()
            }
        }
    }

    private func copyPath() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        var path = targetURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            path = "~" + path.dropFirst(home.count)
        }

        pasteboard.setString(path, forType: .string)
        ToastManager.shared.show("Path copied to clipboard")
    }

    private func moveToTrash() {
        do {
            try FileManager.default.trashItem(at: targetURL, resultingItemURL: nil)
            // Refresh the file list
            manager.refresh()
        } catch {
            print("Error moving to trash: \(error)")
        }
    }

    private func loadApps(for url: URL) {
        let ext = fileType

        // Check cache first
        if let cached = OpenWithCache.shared.getApps(for: ext) {
            allApps = cached
            return
        }

        // Get apps from system (do this async to not block)
        Task {
            let result = await getAppsAsync(for: url, ext: ext)
            allApps = result
            OpenWithCache.shared.setApps(result, for: ext)
        }
    }

    nonisolated private func getAppsAsync(for url: URL, ext: String) async -> [(url: URL, name: String, icon: NSImage)] {
        var appURLs: [URL] = []

        if let apps = LSCopyApplicationURLsForURL(url as CFURL, .all)?.takeRetainedValue() as? [URL] {
            appURLs = apps
        }

        // Filter duplicates and limit to 15
        var seen = Set<String>()
        let filtered: [(url: URL, name: String, icon: NSImage)] = appURLs.compactMap { appURL in
            let name = appURL.deletingPathExtension().lastPathComponent
            if seen.contains(name) { return nil }
            seen.insert(name)
            let icon = NSWorkspace.shared.icon(forFile: appURL.path)
            return (url: appURL, name: name, icon: icon)
        }.prefix(15).map { $0 }

        return Array(filtered)
    }
}

struct ActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(color)
                    .frame(width: 20)

                Text(title)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
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

struct ActionButtonWithIcon: View {
    let icon: NSImage
    let title: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 18, height: 18)

                Text(title)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)

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

struct PreferredAppButton: View {
    let icon: NSImage
    let title: String
    let onOpen: () -> Void
    let onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onOpen) {
                HStack(spacing: 10) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 18, height: 18)

                    Text(title)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)

                    Spacer()
                }
            }
            .buttonStyle(.plain)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.gray.opacity(0.15) : Color.clear)
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - EXIF Metadata Sheet

struct ExifMetadataSheet: View {
    let url: URL
    @Binding var isPresented: Bool
    @State private var metadata: [(key: String, value: String)] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "camera.aperture")
                    .font(.system(size: 20))
                    .foregroundColor(.teal)
                Text("EXIF / Metadata")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            if isLoading {
                VStack {
                    ProgressView()
                    Text("Reading metadata...")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if metadata.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "photo")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("No metadata found")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Metadata table
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(metadata, id: \.key) { item in
                            HStack(alignment: .top) {
                                Text(item.key)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .frame(width: 140, alignment: .trailing)

                                Text(item.value)
                                    .font(.system(size: 12))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)

                            Divider()
                                .padding(.leading, 160)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }

            Divider()

            // Footer
            HStack {
                Text(url.lastPathComponent)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer()
                Button("Close") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 500, height: 500)
        .onAppear { loadMetadata() }
    }

    private func loadMetadata() {
        Task {
            let result = await readExifMetadata(from: url)
            await MainActor.run {
                metadata = result
                isLoading = false
            }
        }
    }

    nonisolated private func readExifMetadata(from url: URL) async -> [(key: String, value: String)] {
        var result: [(key: String, value: String)] = []

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return result
        }

        // Basic image info
        if let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
           let height = properties[kCGImagePropertyPixelHeight as String] as? Int {
            result.append((key: "Dimensions", value: "\(width) x \(height)"))
        }

        if let colorModel = properties[kCGImagePropertyColorModel as String] as? String {
            result.append((key: "Color Model", value: colorModel))
        }

        if let depth = properties[kCGImagePropertyDepth as String] as? Int {
            result.append((key: "Bit Depth", value: "\(depth) bits"))
        }

        if let dpiWidth = properties[kCGImagePropertyDPIWidth as String] as? Double {
            result.append((key: "DPI", value: String(format: "%.0f", dpiWidth)))
        }

        if let orientation = properties[kCGImagePropertyOrientation as String] as? Int {
            let orientationNames = ["", "Normal", "Flip H", "Rotate 180", "Flip V", "Transpose", "Rotate 90 CW", "Transverse", "Rotate 90 CCW"]
            if orientation < orientationNames.count {
                result.append((key: "Orientation", value: orientationNames[orientation]))
            }
        }

        // EXIF data
        if let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            if let dateTime = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String {
                result.append((key: "Date Taken", value: dateTime))
            }

            if let make = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any],
               let cameraMake = make[kCGImagePropertyTIFFMake as String] as? String {
                result.append((key: "Camera Make", value: cameraMake))
            }

            if let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any],
               let model = tiff[kCGImagePropertyTIFFModel as String] as? String {
                result.append((key: "Camera Model", value: model))
            }

            if let fNumber = exif[kCGImagePropertyExifFNumber as String] as? Double {
                result.append((key: "Aperture", value: String(format: "f/%.1f", fNumber)))
            }

            if let exposure = exif[kCGImagePropertyExifExposureTime as String] as? Double {
                if exposure >= 1 {
                    result.append((key: "Exposure", value: String(format: "%.1f sec", exposure)))
                } else {
                    result.append((key: "Exposure", value: "1/\(Int(1/exposure)) sec"))
                }
            }

            if let iso = exif[kCGImagePropertyExifISOSpeedRatings as String] as? [Int], let isoValue = iso.first {
                result.append((key: "ISO", value: "\(isoValue)"))
            }

            if let focalLength = exif[kCGImagePropertyExifFocalLength as String] as? Double {
                result.append((key: "Focal Length", value: String(format: "%.1f mm", focalLength)))
            }

            if let flash = exif[kCGImagePropertyExifFlash as String] as? Int {
                result.append((key: "Flash", value: flash == 0 ? "No Flash" : "Flash Fired"))
            }

            if let lensModel = exif[kCGImagePropertyExifLensModel as String] as? String {
                result.append((key: "Lens", value: lensModel))
            }

            if let software = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any],
               let sw = software[kCGImagePropertyTIFFSoftware as String] as? String {
                result.append((key: "Software", value: sw))
            }
        }

        // GPS data
        if let gps = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any] {
            if let lat = gps[kCGImagePropertyGPSLatitude as String] as? Double,
               let latRef = gps[kCGImagePropertyGPSLatitudeRef as String] as? String,
               let lon = gps[kCGImagePropertyGPSLongitude as String] as? Double,
               let lonRef = gps[kCGImagePropertyGPSLongitudeRef as String] as? String {
                let latDir = latRef == "N" ? "" : "-"
                let lonDir = lonRef == "E" ? "" : "-"
                result.append((key: "GPS", value: "\(latDir)\(String(format: "%.6f", lat)), \(lonDir)\(String(format: "%.6f", lon))"))
            }

            if let altitude = gps[kCGImagePropertyGPSAltitude as String] as? Double {
                result.append((key: "Altitude", value: String(format: "%.1f m", altitude)))
            }
        }

        return result
    }
}

// MARK: - Office Metadata Sheet

struct OfficeMetadataSheet: View {
    let url: URL
    @Binding var isPresented: Bool
    @State private var metadata: [(key: String, value: String)] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 20))
                    .foregroundColor(.indigo)
                Text("Document Info")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            if isLoading {
                VStack {
                    ProgressView()
                    Text("Reading document...")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if metadata.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("No metadata found")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Metadata table
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(metadata, id: \.key) { item in
                            HStack(alignment: .top) {
                                Text(item.key)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .frame(width: 140, alignment: .trailing)

                                Text(item.value)
                                    .font(.system(size: 12))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)

                            Divider()
                                .padding(.leading, 160)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }

            Divider()

            // Footer
            HStack {
                Text(url.lastPathComponent)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer()
                Button("Close") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 500, height: 450)
        .onAppear { loadMetadata() }
    }

    private func loadMetadata() {
        Task {
            let result = await readOfficeMetadata(from: url)
            await MainActor.run {
                metadata = result.metadata
                errorMessage = result.error
                isLoading = false
            }
        }
    }

    nonisolated private func readOfficeMetadata(from url: URL) async -> (metadata: [(key: String, value: String)], error: String?) {
        var result: [(key: String, value: String)] = []
        let ext = url.pathExtension.lowercased()

        // Modern Office formats (docx, xlsx, pptx) are ZIP files
        if ["docx", "xlsx", "pptx"].contains(ext) {
            // Extract and parse docProps/core.xml
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-p", url.path, "docProps/core.xml"]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let xml = String(data: data, encoding: .utf8) {
                    result = parseOfficeXML(xml)
                }

                // Also try app.xml for more info
                let process2 = Process()
                process2.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                process2.arguments = ["-p", url.path, "docProps/app.xml"]

                let pipe2 = Pipe()
                process2.standardOutput = pipe2
                process2.standardError = FileHandle.nullDevice

                try process2.run()
                process2.waitUntilExit()

                let data2 = pipe2.fileHandleForReading.readDataToEndOfFile()
                if let xml2 = String(data: data2, encoding: .utf8) {
                    result.append(contentsOf: parseAppXML(xml2))
                }

            } catch {
                return ([], "Failed to read document: \(error.localizedDescription)")
            }
        } else {
            // Old formats - use mdls
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/mdls")
            process.arguments = [url.path]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    result = parseMdlsOutput(output)
                }
            } catch {
                return ([], "Failed to read document")
            }
        }

        // Add file info
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
            if let size = attrs[.size] as? Int64 {
                result.insert((key: "File Size", value: ByteCountFormatter.string(fromByteCount: size, countStyle: .file)), at: 0)
            }
            if let created = attrs[.creationDate] as? Date {
                result.append((key: "File Created", value: formatDate(created)))
            }
            if let modified = attrs[.modificationDate] as? Date {
                result.append((key: "File Modified", value: formatDate(modified)))
            }
        }

        return (result, nil)
    }

    nonisolated private func parseOfficeXML(_ xml: String) -> [(key: String, value: String)] {
        var result: [(key: String, value: String)] = []

        let mappings: [(tag: String, label: String)] = [
            ("dc:title", "Title"),
            ("dc:creator", "Author"),
            ("cp:lastModifiedBy", "Last Modified By"),
            ("dc:description", "Description"),
            ("dc:subject", "Subject"),
            ("cp:keywords", "Keywords"),
            ("cp:category", "Category"),
            ("dcterms:created", "Created"),
            ("dcterms:modified", "Modified"),
            ("cp:revision", "Revision"),
        ]

        for (tag, label) in mappings {
            if let value = extractXMLValue(xml, tag: tag), !value.isEmpty {
                var displayValue = value
                // Format date strings
                if tag.contains("created") || tag.contains("modified") {
                    if let date = ISO8601DateFormatter().date(from: value) {
                        displayValue = formatDate(date)
                    }
                }
                result.append((key: label, value: displayValue))
            }
        }

        return result
    }

    nonisolated private func parseAppXML(_ xml: String) -> [(key: String, value: String)] {
        var result: [(key: String, value: String)] = []

        let mappings: [(tag: String, label: String)] = [
            ("Application", "Application"),
            ("AppVersion", "App Version"),
            ("Company", "Company"),
            ("Pages", "Pages"),
            ("Words", "Words"),
            ("Characters", "Characters"),
            ("Paragraphs", "Paragraphs"),
            ("Slides", "Slides"),
            ("Notes", "Notes"),
        ]

        for (tag, label) in mappings {
            if let value = extractXMLValue(xml, tag: tag), !value.isEmpty {
                result.append((key: label, value: value))
            }
        }

        return result
    }

    nonisolated private func extractXMLValue(_ xml: String, tag: String) -> String? {
        let pattern = "<\(tag)[^>]*>([^<]*)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              let range = Range(match.range(at: 1), in: xml) else {
            return nil
        }
        return String(xml[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private func parseMdlsOutput(_ output: String) -> [(key: String, value: String)] {
        var result: [(key: String, value: String)] = []
        let lines = output.components(separatedBy: "\n")

        let interestingKeys = [
            "kMDItemTitle": "Title",
            "kMDItemAuthors": "Authors",
            "kMDItemCreator": "Creator",
            "kMDItemDescription": "Description",
            "kMDItemKeywords": "Keywords",
            "kMDItemNumberOfPages": "Pages",
            "kMDItemContentCreationDate": "Created",
            "kMDItemContentModificationDate": "Modified",
        ]

        for line in lines {
            let parts = line.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                var value = parts[1].trimmingCharacters(in: .whitespaces)

                if let label = interestingKeys[key], value != "(null)" {
                    // Clean up array syntax
                    if value.hasPrefix("(") && value.hasSuffix(")") {
                        value = String(value.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                        value = value.replacingOccurrences(of: "\"", with: "")
                        value = value.replacingOccurrences(of: ",\n", with: ", ")
                    }
                    result.append((key: label, value: value))
                }
            }
        }

        return result
    }

    nonisolated private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Image Resize/Crop Sheet

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
                    .font(.system(size: 15, weight: .semibold))
                Spacer()

                // Mode toggle
                Picker("", selection: $isCropMode) {
                    Text("Resize").tag(false)
                    Text("Crop").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)

                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
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

                            // Crop overlay
                            if isCropMode && isDragging {
                                let rect = normalizedCropRect(in: imageSize, offset: CGPoint(x: offsetX, y: offsetY))

                                // Dim outside area
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

                                // Crop border
                                Rectangle()
                                    .stroke(Color.white, lineWidth: 2)
                                    .frame(width: rect.width, height: rect.height)
                                    .position(x: rect.midX, y: rect.midY)

                                // Corner handles
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
                                .onEnded { _ in
                                    if isCropMode {
                                        // Keep the selection visible
                                    }
                                }
                        )
                        .onAppear {
                            imageViewSize = imageSize
                        }
                    }
                }
            }
            .frame(height: 450)

            Divider()

            // Controls
            VStack(spacing: 12) {
                // Size info
                HStack {
                    Text("Original: \(Int(originalSize.width)) × \(Int(originalSize.height))")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                    if !newWidth.isEmpty && !newHeight.isEmpty {
                        Text("New: \(newWidth) × \(newHeight)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.pink)
                    }
                }

                if isCropMode {
                    // Crop instructions
                    if !isDragging {
                        Text("Drag on image to select crop area")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    } else {
                        HStack {
                            Button("Clear Selection") {
                                isDragging = false
                                cropStart = .zero
                                cropEnd = .zero
                            }
                            .font(.system(size: 12))
                        }
                    }
                } else {
                    // Resize presets
                    HStack(spacing: 6) {
                        ForEach(ResizePreset.allCases.filter { $0 != .custom }, id: \.self) { preset in
                            Button(action: { applyPreset(preset) }) {
                                Text(preset.rawValue)
                                    .font(.system(size: 11))
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

                    // Custom size inputs
                    HStack(spacing: 8) {
                        TextField("Width", text: $newWidth)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .onChange(of: newWidth) { _ in
                                if keepAspectRatio, let w = Double(newWidth) {
                                    newHeight = String(Int(w / aspectRatio))
                                }
                            }

                        Image(systemName: keepAspectRatio ? "link" : "link.badge.plus")
                            .font(.system(size: 14))
                            .foregroundColor(keepAspectRatio ? .accentColor : .secondary)
                            .onTapGesture { keepAspectRatio.toggle() }

                        TextField("Height", text: $newHeight)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .onChange(of: newHeight) { _ in
                                if keepAspectRatio, let h = Double(newHeight) {
                                    newWidth = String(Int(h * aspectRatio))
                                }
                            }

                        Text("px")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                }
            }
            .padding(12)

            Divider()

            // Footer
            HStack {
                Text(url.lastPathComponent)
                    .font(.system(size: 11))
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
        case 0: return CGPoint(x: rect.minX, y: rect.minY) // Top-left
        case 1: return CGPoint(x: rect.maxX, y: rect.minY) // Top-right
        case 2: return CGPoint(x: rect.maxX, y: rect.maxY) // Bottom-right
        case 3: return CGPoint(x: rect.minX, y: rect.maxY) // Bottom-left
        default: return .zero
        }
    }

    private func updateCropCorner(corner: Int, location: CGPoint, imageSize: CGSize, offset: CGPoint) {
        switch corner {
        case 0: // Top-left
            cropStart = location
        case 1: // Top-right
            cropEnd.x = location.x
            cropStart.y = location.y
        case 2: // Bottom-right
            cropEnd = location
        case 3: // Bottom-left
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

        // Calculate crop rect in original image coordinates
        let scale = originalSize.width / imageViewSize.width
        let rect = normalizedCropRect(in: imageViewSize, offset: .zero)

        // Adjust for image offset in container
        let imageOffsetX = (600 - imageViewSize.width) / 2  // Approximate container width
        let imageOffsetY = (350 - imageViewSize.height) / 2  // Image view height

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
