import SwiftUI
import AppKit
import ImageIO

struct ActionsPane: View {
    @ObservedObject var manager: FileExplorerManager
    @ObservedObject var settings = AppSettings.shared
    @State private var allApps: [AppInfo] = []
    @State private var showAppSelector = false
    @State private var showOtherApps = false
    @State private var showExifSheet = false
    @State private var showOfficeMetadataSheet = false
    @State private var showImageResizeSheet = false
    @State private var showImageConvertSheet = false

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
        let imageExtensions = ["jpg", "jpeg", "png", "heic", "heif", "tiff", "tif", "gif", "bmp", "webp", "avif"]
        return imageExtensions.contains(targetURL.pathExtension.lowercased())
    }

    private var isOfficeFile: Bool {
        let officeExtensions = ["docx", "xlsx", "pptx", "doc", "xls", "ppt"]
        return officeExtensions.contains(targetURL.pathExtension.lowercased())
    }

    private var openWithLabel: String {
        if isDirectory {
            return "Open folder with"
        }
        let ext = targetURL.pathExtension.lowercased()
        if ext.isEmpty {
            return "Open file with"
        }
        return "Open \(ext) file with"
    }

    private var preferredAppPaths: [String] {
        settings.getPreferredApps(for: fileType)
    }

    private var preferredApps: [AppInfo] {
        preferredAppPaths.compactMap { path -> AppInfo? in
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            let name = url.deletingPathExtension().lastPathComponent
            let icon = NSWorkspace.shared.icon(forFile: path)
            return AppInfo(url: url, name: name, icon: icon)
        }
    }

    private var otherApps: [AppInfo] {
        let preferredSet = Set(preferredAppPaths)
        return allApps.filter { !preferredSet.contains($0.url.path) }
    }

    private func buildRightPaneItems() -> [RightPaneItem] {
        var items: [RightPaneItem] = []
        let url = targetURL
        let inSelection = manager.isInSelection(url)
        items.append(RightPaneItem(id: "selection", title: inSelection ? "Remove from selection" : "Add to selection") { [url] in
            self.manager.toggleFileSelection(url)
        })
        items.append(RightPaneItem(id: "copypath", title: "Copy path") {
            self.copyPath()
        })
        items.append(RightPaneItem(id: "rename", title: "Rename") {
            self.manager.startRename()
        })
        if isImageFile {
            items.append(RightPaneItem(id: "exif", title: "EXIF / Metadata") {
                self.showExifSheet = true
            })
            items.append(RightPaneItem(id: "resize", title: "Resize / Crop") {
                self.showImageResizeSheet = true
            })
            items.append(RightPaneItem(id: "convert", title: "Convert to...") {
                self.showImageConvertSheet = true
            })
        }
        if isOfficeFile {
            items.append(RightPaneItem(id: "office", title: "Document Info") {
                self.showOfficeMetadataSheet = true
            })
        }
        items.append(RightPaneItem(id: "selectapp", title: "Select app...") {
            self.showAppSelector = true
        })
        for app in preferredApps {
            let appURL = app.url
            items.append(RightPaneItem(id: "app-\(app.url.path)", title: app.name) { [url] in
                NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
            })
        }
        return items
    }

    var body: some View {
        let paneItems = buildRightPaneItems()

        VStack(alignment: .leading, spacing: 0) {
            // File/Folder header with icon + name
            HStack(spacing: 8) {
                Image(nsImage: IconProvider.shared.icon(for: targetURL, isDirectory: isDirectory))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 20, height: 20)

                Text(targetName)
                    .font(.system(size: 14))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            VStack(spacing: 2) {
                ActionButton(
                    icon: manager.isInSelection(targetURL) ? "minus.circle" : "checkmark.circle",
                    title: manager.isInSelection(targetURL) ? "Remove from selection" : "Add to selection",
                    color: manager.isInSelection(targetURL) ? .red : .green,
                    flatIndex: 0,
                    manager: manager
                ) {
                    manager.toggleFileSelection(targetURL)
                }

                ActionButton(
                    icon: "doc.on.doc",
                    title: "Copy path",
                    color: .blue,
                    flatIndex: 1,
                    manager: manager
                ) {
                    copyPath()
                }

                ActionButton(
                    icon: "pencil",
                    title: "Rename",
                    color: .orange,
                    flatIndex: 2,
                    manager: manager
                ) {
                    manager.startRename()
                }

                // EXIF for images
                if isImageFile {
                    let base = 3
                    ActionButton(
                        icon: "camera.aperture",
                        title: "EXIF / Metadata",
                        color: .teal,
                        flatIndex: base,
                        manager: manager
                    ) {
                        showExifSheet = true
                    }

                    ActionButton(
                        icon: "arrow.up.left.and.arrow.down.right",
                        title: "Resize / Crop",
                        color: .pink,
                        flatIndex: base + 1,
                        manager: manager
                    ) {
                        showImageResizeSheet = true
                    }

                    ActionButton(
                        icon: "arrow.triangle.2.circlepath",
                        title: "Convert to...",
                        color: .cyan,
                        flatIndex: base + 2,
                        manager: manager
                    ) {
                        showImageConvertSheet = true
                    }
                }

                // Office metadata
                if isOfficeFile {
                    let base = 3
                    ActionButton(
                        icon: "doc.text.magnifyingglass",
                        title: "Document Info",
                        color: .indigo,
                        flatIndex: base,
                        manager: manager
                    ) {
                        showOfficeMetadataSheet = true
                    }
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 8)

            Divider()

            VStack(alignment: .leading, spacing: 2) {
                Text(openWithLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                let selectAppIdx = paneItems.firstIndex(where: { $0.id == "selectapp" }) ?? -1
                ActionButton(
                    icon: "app.badge",
                    title: "Select app...",
                    color: .purple,
                    flatIndex: selectAppIdx,
                    manager: manager
                ) {
                    showAppSelector = true
                }

                if !preferredApps.isEmpty {
                    ForEach(Array(preferredApps.enumerated()), id: \.element.url.path) { idx, app in
                        let appIdx = paneItems.firstIndex(where: { $0.id == "app-\(app.url.path)" }) ?? -1
                        PreferredAppButton(
                            icon: app.icon,
                            title: app.name,
                            appURL: app.url,
                            flatIndex: appIdx,
                            manager: manager,
                            onOpen: {
                                NSWorkspace.shared.open([targetURL], withApplicationAt: app.url, configuration: NSWorkspace.OpenConfiguration())
                            },
                            onRemove: {
                                settings.removePreferredApp(for: fileType, appPath: app.url.path)
                            }
                        )
                    }
                }

                if !otherApps.isEmpty {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showOtherApps.toggle()
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: showOtherApps ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                            Text("macOS suggested apps (\(otherApps.count))")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)

                    if showOtherApps {
                        ForEach(otherApps, id: \.url.path) { app in
                            ActionButtonWithIcon(
                                icon: app.icon,
                                title: app.name,
                                appURL: app.url
                            ) {
                                settings.addPreferredApp(for: fileType, appPath: app.url.path)
                                NSWorkspace.shared.open([targetURL], withApplicationAt: app.url, configuration: NSWorkspace.OpenConfiguration())
                            }
                        }
                    }
                }

                if allApps.isEmpty {
                    HStack(spacing: 4) {
                        Text("No suggested apps")
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
        }
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: targetURL) { newURL in
            loadApps(for: newURL)
            manager.rightPaneItems = buildRightPaneItems()
        }
        .onChange(of: manager.rightPaneFocused) { _ in
            manager.rightPaneItems = buildRightPaneItems()
        }
        .onAppear {
            loadApps(for: targetURL)
            manager.rightPaneItems = buildRightPaneItems()
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
        .sheet(isPresented: $showImageConvertSheet) {
            ImageConvertSheet(url: targetURL, isPresented: $showImageConvertSheet) {
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
        allApps = AppSearcher.shared.appsForFile(url)
    }
}

struct ActionButton: View {
    let icon: String
    let title: String
    let color: Color
    var flatIndex: Int = -1
    var manager: FileExplorerManager? = nil
    let action: () -> Void

    @State private var isHovered = false

    private var isFocused: Bool {
        guard let m = manager else { return false }
        return m.rightPaneFocused && m.rightPaneIndex == flatIndex && flatIndex >= 0
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(isFocused ? .white : color)
                    .frame(width: 22, height: 22)

                Text(title)
                    .font(.system(size: 14))
                    .foregroundColor(isFocused ? .white : .primary)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isFocused ? Color.accentColor : (isHovered ? Color.gray.opacity(0.15) : Color.clear))
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
    var appURL: URL? = nil
    let action: () -> Void

    @State private var isHovered = false
    @State private var isDragTarget = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 22, height: 22)

                Text(title)
                    .font(.system(size: 14))
                    .foregroundColor(.primary)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isDragTarget ? Color.accentColor.opacity(0.2) :
                          (isHovered ? Color.gray.opacity(0.15) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isDragTarget ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .onDrop(of: [.fileURL], isTargeted: $isDragTarget) { providers in
            guard let app = appURL else { return false }
            for provider in providers {
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                    guard let data = item as? Data,
                          let fileURL = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    DispatchQueue.main.async {
                        NSWorkspace.shared.open([fileURL], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
                    }
                }
            }
            return true
        }
    }
}

struct PreferredAppButton: View {
    let icon: NSImage
    let title: String
    let appURL: URL
    var flatIndex: Int = -1
    var manager: FileExplorerManager? = nil
    let onOpen: () -> Void
    let onRemove: () -> Void

    @State private var isHovered = false
    @State private var isDragTarget = false

    private var isFocused: Bool {
        guard let m = manager else { return false }
        return m.rightPaneFocused && m.rightPaneIndex == flatIndex && flatIndex >= 0
    }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onOpen) {
                HStack(spacing: 10) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 22, height: 22)

                    Text(title)
                        .font(.system(size: 14))
                        .foregroundColor(isFocused ? .white : .primary)

                    Spacer()
                }
            }
            .buttonStyle(.plain)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(isFocused ? .white.opacity(0.7) : .secondary)
            }
            .buttonStyle(.plain)
            .opacity(isHovered || isFocused ? 1 : 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isFocused ? Color.accentColor :
                      (isDragTarget ? Color.accentColor.opacity(0.2) :
                      (isHovered ? Color.gray.opacity(0.15) : Color.clear)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isDragTarget ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .onDrop(of: [.fileURL], isTargeted: $isDragTarget) { providers in
            handleDrop(providers: providers)
            return true
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        let app = appURL
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                guard let data = item as? Data,
                      let fileURL = URL(dataRepresentation: data, relativeTo: nil) else { return }
                DispatchQueue.main.async {
                    NSWorkspace.shared.open([fileURL], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
                }
            }
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
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if metadata.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "photo")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("No metadata found")
                        .font(.system(size: 14))
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
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .frame(width: 140, alignment: .trailing)

                                Text(item.value)
                                    .font(.system(size: 13))
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
                    .font(.system(size: 13))
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
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if metadata.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("No metadata found")
                        .font(.system(size: 14))
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
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .frame(width: 140, alignment: .trailing)

                                Text(item.value)
                                    .font(.system(size: 13))
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
                    .font(.system(size: 13))
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
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Spacer()
                    if !newWidth.isEmpty && !newHeight.isEmpty {
                        Text("New: \(newWidth) × \(newHeight)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.pink)
                    }
                }

                if isCropMode {
                    // Crop instructions
                    if !isDragging {
                        Text("Drag on image to select crop area")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    } else {
                        HStack {
                            Button("Clear Selection") {
                                isDragging = false
                                cropStart = .zero
                                cropEnd = .zero
                            }
                            .font(.system(size: 13))
                        }
                    }
                } else {
                    // Resize presets
                    HStack(spacing: 6) {
                        ForEach(ResizePreset.allCases.filter { $0 != .custom }, id: \.self) { preset in
                            Button(action: { applyPreset(preset) }) {
                                Text(preset.rawValue)
                                    .font(.system(size: 13))
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
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundColor(.red)
                }
            }
            .padding(12)

            Divider()

            // Footer
            HStack {
                Text(url.lastPathComponent)
                    .font(.system(size: 13))
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

// MARK: - Image Convert Sheet

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
            // Header
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 18))
                    .foregroundColor(.cyan)
                Text("Convert Image")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))

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
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    Spacer()
                }

                HStack(spacing: 12) {
                    Label(sourceExtension.uppercased(), systemImage: "doc.fill")
                        .font(.system(size: 13))
                    Text("\(Int(originalSize.width)) x \(Int(originalSize.height))")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Text(originalFileSize)
                        .font(.system(size: 13))
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
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    Spacer()
                }

                // Format grid
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(availableFormats) { format in
                        Button(action: { selectedFormat = format }) {
                            Text(format.rawValue)
                                .font(.system(size: 13, weight: selectedFormat == format ? .semibold : .regular))
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

                // Quality slider
                if selectedFormat.supportsQuality {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Quality")
                                .font(.system(size: 13))
                            Spacer()
                            Text("\(Int(quality * 100))%")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $quality, in: 0.1...1.0, step: 0.05)
                        HStack {
                            Text("Smaller file")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("Better quality")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Alpha option
                if selectedFormat.supportsAlpha {
                    Toggle("Preserve transparency", isOn: $preserveAlpha)
                        .font(.system(size: 13))
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
                        .font(.system(size: 12))
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
            // Pre-select a sensible default
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

                // Build output path
                let dir = url.deletingLastPathComponent()
                let baseName = url.deletingPathExtension().lastPathComponent
                var outputURL = dir.appendingPathComponent("\(baseName).\(format.fileExtension)")

                // Avoid overwriting: add suffix if exists
                var counter = 1
                while FileManager.default.fileExists(atPath: outputURL.path) {
                    outputURL = dir.appendingPathComponent("\(baseName)-\(counter).\(format.fileExtension)")
                    counter += 1
                }

                // Convert
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

                // Handle alpha: for JPEG/BMP that don't support alpha, composite on white
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

                // Get output size
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

        // Fill white background
        context.setFillColor(CGColor.white)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Draw image on top
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
