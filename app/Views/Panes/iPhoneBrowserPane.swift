import SwiftUI

struct iPhoneBrowserPane: View {
    @ObservedObject var manager: FileExplorerManager
    @ObservedObject var deviceManager = iPhoneManager.shared
    @ObservedObject var settings = AppSettings.shared
    @State private var searchText: String = ""
    @State private var previewURL: URL?
    @State private var isLoadingPreview: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Show different content based on view mode
            switch manager.browserViewMode {
            case .files:
                iPhoneFilesContent(
                    manager: manager,
                    deviceManager: deviceManager,
                    settings: settings,
                    searchText: $searchText,
                    previewURL: $previewURL,
                    isLoadingPreview: $isLoadingPreview
                )
            case .selected:
                SelectedFilesView(manager: manager)
            }
        }
        .onChange(of: deviceManager.browseMode) { _ in
            searchText = ""
            previewURL = nil
        }
        .onChange(of: deviceManager.selectedFile) { newFile in
            Task {
                await loadPreview(for: newFile)
            }
        }
    }

    private func loadPreview(for file: iPhoneFile?) async {
        previewURL = nil

        guard let file = file, !file.isDirectory else { return }

        // Check if file type is previewable
        let ext = (file.name as NSString).pathExtension.lowercased()
        let previewableExtensions = Set([
            "jpg", "jpeg", "png", "gif", "bmp", "webp", "heic", "tiff", "avif",
            "txt", "md", "json", "xml", "yaml", "yml",
            "py", "js", "ts", "swift", "rb", "go", "rs", "c", "cpp", "h",
            "html", "css", "sh", "log",
            "mp3", "m4a", "wav", "aac", "flac", "ogg", "aiff",
            "mp4", "mov", "m4v"
        ])

        guard previewableExtensions.contains(ext) else { return }

        isLoadingPreview = true
        defer { isLoadingPreview = false }

        // Download file for preview
        if let localURL = await deviceManager.downloadFile(file) {
            previewURL = localURL
        }
    }
}

// MARK: - iPhone Files Content (main browser view)

struct iPhoneFilesContent: View {
    @ObservedObject var manager: FileExplorerManager
    @ObservedObject var deviceManager: iPhoneManager
    @ObservedObject var settings: AppSettings
    @Binding var searchText: String
    @Binding var previewURL: URL?
    @Binding var isLoadingPreview: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Breadcrumb / path bar
            iPhoneBreadcrumbView(manager: manager, deviceManager: deviceManager)

            Divider()

            // Search bar
            iPhoneSearchBar(searchText: $searchText)

            Divider()

            // Content
            if deviceManager.isLoadingFiles {
                Spacer()
                ProgressView("Loading...")
                Spacer()
            } else {
                switch deviceManager.browseMode {
                case .apps:
                    iPhoneAppListView(manager: manager, deviceManager: deviceManager, searchText: searchText)
                case .appDocuments:
                    if settings.showPreviewPane {
                        ResizableSplitView(
                            top: {
                                iPhoneFileListView(manager: manager, deviceManager: deviceManager, searchText: searchText)
                            },
                            bottom: {
                                iPhonePreviewPane(previewURL: previewURL, isLoading: isLoadingPreview, deviceManager: deviceManager)
                            }
                        )
                    } else {
                        iPhoneFileListView(manager: manager, deviceManager: deviceManager, searchText: searchText)
                    }
                }
            }
        }
        .onChange(of: deviceManager.browseMode) { _ in
            searchText = ""
            previewURL = nil
        }
        .onChange(of: deviceManager.selectedFile) { newFile in
            Task {
                await loadPreview(for: newFile)
            }
        }
    }

    private func loadPreview(for file: iPhoneFile?) async {
        previewURL = nil

        guard let file = file, !file.isDirectory else { return }

        let ext = (file.name as NSString).pathExtension.lowercased()
        let previewableExtensions = Set([
            "jpg", "jpeg", "png", "gif", "bmp", "webp", "heic", "tiff", "avif",
            "txt", "md", "json", "xml", "yaml", "yml",
            "py", "js", "ts", "swift", "rb", "go", "rs", "c", "cpp", "h",
            "html", "css", "sh", "log",
            "mp3", "m4a", "wav", "aac", "flac", "ogg", "aiff",
            "mp4", "mov", "m4v"
        ])

        guard previewableExtensions.contains(ext) else { return }

        isLoadingPreview = true
        defer { isLoadingPreview = false }

        if let localURL = await deviceManager.downloadFile(file) {
            previewURL = localURL
        }
    }
}

// MARK: - iPhone Gallery Content

struct iPhoneGalleryContent: View {
    @ObservedObject var deviceManager: iPhoneManager

    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "bmp", "webp", "heic", "heif", "tiff", "tif", "avif"]

    private var imageFiles: [iPhoneFile] {
        deviceManager.files.filter { file in
            let ext = (file.name as NSString).pathExtension.lowercased()
            return Self.imageExtensions.contains(ext)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            iPhoneBreadcrumbView(manager: nil, deviceManager: deviceManager)
            Divider()

            if case .apps = deviceManager.browseMode {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Select an app to view images")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if imageFiles.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No images in this folder")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 12) {
                        ForEach(imageFiles) { file in
                            iPhoneGalleryThumbnail(file: file, deviceManager: deviceManager)
                        }
                    }
                    .padding(16)
                }
            }
        }
    }
}

struct iPhoneGalleryThumbnail: View {
    let file: iPhoneFile
    @ObservedObject var deviceManager: iPhoneManager
    @State private var thumbnailImage: NSImage?
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                if let image = thumbnailImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 150, height: 150)
                        .clipped()
                        .cornerRadius(8)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 150, height: 150)
                        .cornerRadius(8)
                        .overlay {
                            if isLoading {
                                ProgressView()
                            } else {
                                Image(systemName: "photo")
                                    .font(.system(size: 32))
                                    .foregroundColor(.secondary)
                            }
                        }
                }
            }

            Text(file.name)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundColor(.secondary)
        }
        .onAppear {
            loadThumbnail()
        }
        .onTapGesture {
            deviceManager.selectedFile = file
        }
    }

    private func loadThumbnail() {
        guard thumbnailImage == nil && !isLoading else { return }
        isLoading = true

        Task {
            if let localURL = await deviceManager.downloadFile(file),
               let image = NSImage(contentsOf: localURL) {
                // Resize for thumbnail
                let thumbSize = NSSize(width: 150, height: 150)
                let resized = NSImage(size: thumbSize)
                resized.lockFocus()
                image.draw(in: NSRect(origin: .zero, size: thumbSize),
                          from: NSRect(origin: .zero, size: image.size),
                          operation: .copy,
                          fraction: 1.0)
                resized.unlockFocus()
                thumbnailImage = resized
            }
            isLoading = false
        }
    }
}

// MARK: - iPhone Search Content

struct iPhoneSearchContent: View {
    @ObservedObject var manager: FileExplorerManager
    @ObservedObject var deviceManager: iPhoneManager
    @State private var searchQuery: String = ""
    @State private var searchResults: [iPhoneFile] = []
    @State private var isSearching: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            iPhoneBreadcrumbView(manager: nil, deviceManager: deviceManager)
            Divider()

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search in app...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        performSearch()
                    }
                if isSearching {
                    ProgressView()
                        .scaleEffect(0.7)
                }
                if !searchQuery.isEmpty {
                    Button(action: {
                        searchQuery = ""
                        searchResults = []
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            if case .apps = deviceManager.browseMode {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Select an app to search its files")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if searchResults.isEmpty && !searchQuery.isEmpty && !isSearching {
                VStack {
                    Spacer()
                    Text("No results found")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else if searchResults.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Enter a search term")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(searchResults) { file in
                            iPhoneSearchResultRow(file: file, deviceManager: deviceManager)
                        }
                    }
                }
            }
        }
    }

    private func performSearch() {
        guard !searchQuery.isEmpty else { return }
        isSearching = true
        searchResults = []

        let query = searchQuery.lowercased()

        // Search current files (non-recursive for now)
        searchResults = deviceManager.files.filter { file in
            file.name.lowercased().contains(query)
        }

        isSearching = false
    }
}

struct iPhoneSearchResultRow: View {
    let file: iPhoneFile
    @ObservedObject var deviceManager: iPhoneManager
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: file.isDirectory ? "folder.fill" : "doc.fill")
                .foregroundColor(file.isDirectory ? .blue : .secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.system(size: 13))
                Text(file.path)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isHovered ? Color.gray.opacity(0.1) : Color.clear)
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            deviceManager.selectedFile = file
        }
    }
}

struct iPhonePreviewPane: View {
    let previewURL: URL?
    let isLoading: Bool
    @ObservedObject var deviceManager: iPhoneManager

    var body: some View {
        if isLoading {
            VStack {
                ProgressView("Loading preview...")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let url = previewURL {
            // Check if it's audio - use iPhone-aware audio preview
            let ext = url.pathExtension.lowercased()
            let audioExtensions = Set(["mp3", "m4a", "wav", "aac", "flac", "ogg", "aiff"])

            if audioExtensions.contains(ext) {
                iPhoneAudioPreviewView(url: url, deviceManager: deviceManager)
            } else {
                PreviewPane(url: url)
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "eye.slash")
                    .font(.system(size: 32))
                    .foregroundColor(.secondary)
                Text("Select a file to preview")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - iPhone Audio Preview with upload-back support

struct iPhoneAudioPreviewView: View {
    let url: URL
    @ObservedObject var deviceManager: iPhoneManager
    @StateObject private var player = AudioPlayerManager()
    @State private var isUploading = false

    var body: some View {
        VStack(spacing: 0) {
            PreviewHeader(title: "Audio preview", icon: "music.note", color: .pink)
            Divider()

            ScrollView {
                VStack(spacing: 20) {
                    // Album art or placeholder
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.1))
                            .frame(width: 150, height: 150)

                        if let artwork = player.artwork {
                            Image(nsImage: artwork)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 150, height: 150)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        } else {
                            Image(systemName: "music.note")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                        }
                    }

                    // Track info
                    VStack(spacing: 4) {
                        Text(player.title ?? url.deletingPathExtension().lastPathComponent)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)

                        if let artist = player.artist {
                            Text(artist)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }

                    // Progress bar
                    VStack(spacing: 4) {
                        Slider(value: $player.currentTime, in: 0...max(player.duration, 1)) { editing in
                            if !editing {
                                player.seek(to: player.currentTime)
                            }
                        }
                        .accentColor(.pink)

                        HStack {
                            Text(formatTime(player.currentTime))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(formatTime(player.duration))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 16)

                    // Controls
                    HStack(spacing: 24) {
                        Button(action: { player.skipBackward() }) {
                            Image(systemName: "gobackward.10")
                                .font(.system(size: 20))
                                .foregroundColor(.primary)
                        }
                        .buttonStyle(.plain)

                        Button(action: { player.togglePlayPause() }) {
                            Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 44))
                                .foregroundColor(.pink)
                        }
                        .buttonStyle(.plain)

                        Button(action: { player.skipForward() }) {
                            Image(systemName: "goforward.10")
                                .font(.system(size: 20))
                                .foregroundColor(.primary)
                        }
                        .buttonStyle(.plain)
                    }

                    // Crop controls for iPhone
                    if player.currentTime > 0 && player.currentTime < player.duration {
                        Divider()
                            .padding(.vertical, 4)

                        VStack(spacing: 8) {
                            Text("Trim & sync to iPhone")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.secondary)
                                .textCase(.uppercase)

                            HStack(spacing: 8) {
                                Button(action: {
                                    Task {
                                        await cropAndUpload(keepFrom: player.currentTime, keepTo: nil)
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "scissors")
                                        Text("Cut start")
                                    }
                                    .font(.system(size: 12))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.orange.opacity(0.15))
                                    .foregroundColor(.orange)
                                    .cornerRadius(5)
                                }
                                .buttonStyle(.plain)

                                Button(action: {
                                    Task {
                                        await cropAndUpload(keepFrom: 0, keepTo: player.currentTime)
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "scissors")
                                        Text("Cut end")
                                    }
                                    .font(.system(size: 12))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.orange.opacity(0.15))
                                    .foregroundColor(.orange)
                                    .cornerRadius(5)
                                }
                                .buttonStyle(.plain)
                            }

                            if player.isCropping || isUploading {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                    Text(isUploading ? "Uploading to iPhone..." : "Processing...")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                            }

                            if let cropMessage = player.cropMessage {
                                Text(cropMessage)
                                    .font(.system(size: 10))
                                    .foregroundColor(player.cropSuccess ? .green : .red)
                                    .multilineTextAlignment(.center)
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .onAppear {
            player.load(url: url)
        }
        .onDisappear {
            player.stop()
        }
        .onChange(of: url) { newURL in
            player.load(url: newURL)
        }
    }

    private func formatTime(_ time: Double) -> String {
        guard time.isFinite && time >= 0 else { return "0:00" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func cropAndUpload(keepFrom: Double, keepTo: Double?) async {
        // First crop locally
        if let endTime = keepTo {
            await player.cropToEnd(url: url, from: endTime)
        } else {
            await player.cropFromStart(url: url, to: keepFrom)
        }

        // If crop succeeded, upload back to iPhone
        guard player.cropSuccess else { return }

        guard let selectedFile = deviceManager.selectedFile,
              let device = deviceManager.currentDevice,
              case .appDocuments(let appId, _) = deviceManager.browseMode else {
            player.cropMessage = "Trimmed locally (couldn't sync to iPhone)"
            return
        }

        isUploading = true

        // Get the parent directory path for upload
        let parentPath = (selectedFile.path as NSString).deletingLastPathComponent

        // Upload the cropped file back (will replace since same name)
        let success = await deviceManager.uploadFileFromContext(
            deviceId: device.id,
            appId: appId,
            localURL: url,
            toPath: parentPath
        )

        isUploading = false

        if success {
            player.cropMessage = "Trimmed & synced to iPhone!"
            player.cropSuccess = true
            // Refresh the file list
            await deviceManager.loadFiles()
        } else {
            player.cropMessage = "Trimmed locally, but failed to sync to iPhone"
        }
    }
}

struct iPhoneSearchBar: View {
    @Binding var searchText: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 13))

            TextField("Filter...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
    }
}

struct iPhoneBreadcrumbView: View {
    var manager: FileExplorerManager?
    @ObservedObject var deviceManager: iPhoneManager

    var body: some View {
        HStack(spacing: 4) {
            // Back to local files button (only if manager available)
            if let manager = manager {
                Button(action: {
                    deviceManager.currentDevice = nil
                    manager.currentPane = .browser
                }) {
                    Image(systemName: "arrow.left.circle")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .help("Back to local files")
            }

            Image(systemName: "iphone")
                .font(.system(size: 12))
                .foregroundColor(.pink)

            // Device name
            Text(deviceManager.currentDevice?.name ?? "iPhone")
                .font(.system(size: 13))
                .foregroundColor(deviceManager.browseMode == .apps ? .primary : .blue)
                .onTapGesture {
                    deviceManager.backToApps()
                }

            // App name if browsing app documents
            if case .appDocuments(_, let appName) = deviceManager.browseMode {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Text(appName)
                    .font(.system(size: 13))
                    .foregroundColor(deviceManager.currentPath == basePath ? .primary : .blue)
                    .onTapGesture {
                        Task {
                            await deviceManager.navigateTo(basePath)
                        }
                    }

                // Path components (folders beyond /Documents)
                ForEach(pathComponents, id: \.path) { component in
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    Text(component.name)
                        .font(.system(size: 13))
                        .foregroundColor(component.path == deviceManager.currentPath ? .primary : .blue)
                        .onTapGesture {
                            Task {
                                await deviceManager.navigateTo(component.path)
                            }
                        }
                }
            }

            Spacer()

            // Refresh button
            Button(action: {
                Task {
                    switch deviceManager.browseMode {
                    case .apps:
                        await deviceManager.loadApps()
                    case .appDocuments:
                        await deviceManager.loadFiles()
                    }
                }
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Refresh")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    private let basePath = "/Documents"

    private var pathComponents: [(name: String, path: String)] {
        var components: [(String, String)] = []
        var current = deviceManager.currentPath

        // Stop at /Documents base path
        while current != basePath && current != "/" && !current.isEmpty {
            let name = (current as NSString).lastPathComponent
            components.insert((name, current), at: 0)
            current = (current as NSString).deletingLastPathComponent
            if current.isEmpty { current = "/" }
        }

        return components
    }
}

// MARK: - App List View

struct iPhoneAppListView: View {
    @ObservedObject var manager: FileExplorerManager
    @ObservedObject var deviceManager: iPhoneManager
    var searchText: String

    private var filteredApps: [iPhoneApp] {
        if searchText.isEmpty {
            return deviceManager.apps
        }
        let query = searchText.lowercased()
        return deviceManager.apps.filter {
            $0.name.lowercased().contains(query) || $0.id.lowercased().contains(query)
        }
    }

    var body: some View {
        if deviceManager.apps.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "app.badge.checkmark")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("No apps with file sharing")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text("Apps need \"UIFileSharingEnabled\" to share documents")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredApps.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("No matching apps")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredApps) { app in
                        iPhoneAppRow(app: app, deviceManager: deviceManager)
                    }
                }
            }
        }
    }
}

struct iPhoneAppRow: View {
    let app: iPhoneApp
    @ObservedObject var deviceManager: iPhoneManager
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "app.fill")
                .font(.system(size: 24))
                .foregroundColor(.blue)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.system(size: 13, weight: .medium))

                Text(app.id)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if !app.version.isEmpty {
                Text("v\(app.version)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isHovered ? Color.gray.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            Task {
                await deviceManager.selectApp(app)
            }
        }
    }
}

// MARK: - File List View

struct iPhoneFileListView: View {
    @ObservedObject var manager: FileExplorerManager
    @ObservedObject var deviceManager: iPhoneManager
    var searchText: String

    private var filteredFiles: [iPhoneFile] {
        if searchText.isEmpty {
            return deviceManager.files
        }
        let query = searchText.lowercased()
        return deviceManager.files.filter { $0.name.lowercased().contains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Table header
            iPhoneTableHeaderView()
            Divider()

            if deviceManager.files.isEmpty {
                Spacer()
                Text("No files")
                    .foregroundColor(.secondary)
                Spacer()
            } else if filteredFiles.isEmpty {
                Spacer()
                Text("No matching files")
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredFiles) { file in
                            iPhoneFileRow(file: file, manager: manager, deviceManager: deviceManager)
                        }
                    }
                }
            }
        }
    }
}

struct iPhoneTableHeaderView: View {
    var body: some View {
        HStack(spacing: 0) {
            Text("Name")
                .frame(minWidth: 250, alignment: .leading)

            Spacer()

            Text("Size")
                .frame(width: 100, alignment: .trailing)

            Text("Modified ago")
                .frame(width: 180, alignment: .leading)
                .padding(.leading, 16)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundColor(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
    }
}

struct iPhoneFileRow: View {
    let file: iPhoneFile
    @ObservedObject var manager: FileExplorerManager
    @ObservedObject var deviceManager: iPhoneManager
    @State private var isHovered = false
    @State private var isDownloading = false

    private var isSelected: Bool {
        deviceManager.isSelected(file)
    }

    private var isCurrentSelection: Bool {
        deviceManager.selectedFile?.path == file.path
    }

    var body: some View {
        HStack(spacing: 0) {
            // Selection indicator
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.green)
                    .frame(width: 20)
            } else {
                Color.clear.frame(width: 20)
            }

            HStack(spacing: 8) {
                Image(systemName: file.isDirectory ? "folder.fill" : fileIcon(for: file.name))
                    .font(.system(size: 16))
                    .foregroundColor(file.isDirectory ? .blue : .secondary)
                    .frame(width: 24)

                Text(file.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if isDownloading {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 16, height: 16)
                }
            }
            .frame(minWidth: 230, alignment: .leading)

            Spacer()

            Text(file.isDirectory ? "--" : formatFileSize(file.size))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .trailing)

            Text(formatDate(file.modifiedDate))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 180, alignment: .leading)
                .padding(.leading, 16)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(
            isCurrentSelection ? Color.accentColor.opacity(0.2) :
            (isSelected ? Color.green.opacity(0.1) :
            (isHovered ? Color.gray.opacity(0.1) : Color.clear))
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture(count: 2) {
            Task {
                await handleDoubleTap()
            }
        }
        .onTapGesture(count: 1) {
            deviceManager.selectedFile = file
        }
    }

    private func handleDoubleTap() async {
        if file.isDirectory {
            await deviceManager.navigateTo(file.path)
        } else {
            isDownloading = true
            if let localURL = await deviceManager.downloadFile(file) {
                NSWorkspace.shared.open(localURL)
            }
            isDownloading = false
        }
    }

    private func fileIcon(for name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "gif", "heic", "webp":
            return "photo"
        case "mp4", "mov", "m4v", "avi":
            return "film"
        case "mp3", "m4a", "wav", "aac":
            return "music.note"
        case "pdf":
            return "doc.text"
        case "txt", "md", "json", "xml":
            return "doc.plaintext"
        case "zip", "tar", "gz":
            return "doc.zipper"
        default:
            return "doc"
        }
    }

    private func formatFileSize(_ size: Int64) -> String {
        if size < 1024 {
            return "\(size) B"
        } else if size < 1024 * 1024 {
            return String(format: "%.1f KB", Double(size) / 1024)
        } else if size < 1024 * 1024 * 1024 {
            return String(format: "%.1f MB", Double(size) / (1024 * 1024))
        } else {
            return String(format: "%.1f GB", Double(size) / (1024 * 1024 * 1024))
        }
    }

    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "--" }

        let now = Date()
        let interval = now.timeIntervalSince(date)

        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let mins = Int(interval / 60)
            return "\(mins) minute\(mins == 1 ? "" : "s")"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            let mins = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)
            if mins > 0 {
                return "\(hours) hour\(hours == 1 ? "" : "s") & \(mins) min"
            }
            return "\(hours) hour\(hours == 1 ? "" : "s")"
        } else if interval < 86400 * 30 {
            let days = Int(interval / 86400)
            let hours = Int((interval.truncatingRemainder(dividingBy: 86400)) / 3600)
            if hours > 0 && days < 7 {
                return "\(days) day\(days == 1 ? "" : "s") & \(hours) hour\(hours == 1 ? "" : "s")"
            }
            return "\(days) day\(days == 1 ? "" : "s")"
        } else if interval < 86400 * 365 {
            let months = Int(interval / (86400 * 30))
            let days = Int((interval.truncatingRemainder(dividingBy: 86400 * 30)) / 86400)
            if days > 0 && months < 6 {
                return "\(months) month\(months == 1 ? "" : "s") & \(days) day\(days == 1 ? "" : "s")"
            }
            return "\(months) month\(months == 1 ? "" : "s")"
        } else {
            let years = Int(interval / (86400 * 365))
            let months = Int((interval.truncatingRemainder(dividingBy: 86400 * 365)) / (86400 * 30))
            if months > 0 {
                return "\(years) year\(years == 1 ? "" : "s") & \(months) month\(months == 1 ? "" : "s")"
            }
            return "\(years) year\(years == 1 ? "" : "s")"
        }
    }
}
