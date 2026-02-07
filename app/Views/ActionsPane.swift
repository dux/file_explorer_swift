import SwiftUI
import AppKit

struct ActionsPane: View {
    @ObservedObject var manager: FileExplorerManager
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject private var selection = SelectionManager.shared
    @State private var allApps: [AppInfo] = []
    @State private var showAppSelector = false
    @State private var showOtherApps = false
    @State private var showExifSheet = false
    @State private var showOfficeMetadataSheet = false
    @State private var showImageResizeSheet = false
    @State private var showImageConvertSheet = false
    @State private var showUninstallConfirm = false
    @State private var appDataPaths: [URL] = []
    @State private var showEmojiPicker = false
    @ObservedObject private var folderIconManager = FolderIconManager.shared

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

    private var isAppBundle: Bool {
        targetURL.pathExtension.lowercased() == "app" && isDirectory
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
        let _ = selection.version
        let paneItems = buildRightPaneItems()

        VStack(alignment: .leading, spacing: 0) {
            // File/Folder header with icon + name
            HStack(spacing: 8) {
                if isDirectory {
                    FolderIconView(url: targetURL, size: 20)
                } else {
                    Image(nsImage: IconProvider.shared.icon(for: targetURL, isDirectory: false))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 20, height: 20)
                }

                Text(targetName)
                    .font(.system(size: 14))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            VStack(spacing: 4) {
                ActionButton(
                    icon: selection.containsLocal(targetURL) ? "minus.circle" : "checkmark.circle",
                    title: selection.containsLocal(targetURL) ? "Remove from selection" : "Add to selection",
                    color: selection.containsLocal(targetURL) ? .red : .green,
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

                if isDirectory && !isAppBundle {
                    ActionButton(
                        icon: "face.smiling",
                        title: "Assign icon",
                        color: .purple,
                        flatIndex: 3,
                        manager: manager
                    ) {
                        showEmojiPicker = true
                    }
                    .popover(isPresented: $showEmojiPicker, arrowEdge: .leading) {
                        EmojiPickerView(
                            folderURL: targetURL,
                            onSelect: { emoji in
                                folderIconManager.setEmoji(emoji, for: targetURL)
                            },
                            onRemove: {
                                folderIconManager.removeEmoji(for: targetURL)
                            },
                            onDismiss: { showEmojiPicker = false },
                            hasExisting: folderIconManager.emoji(for: targetURL) != nil
                        )
                        .interactiveDismissDisabled()
                    }
                }

                if isAppBundle {
                    ActionButton(
                        icon: "trash",
                        title: "Uninstall \(targetURL.deletingPathExtension().lastPathComponent)",
                        color: .red,
                        flatIndex: 3,
                        manager: manager
                    ) {
                        appDataPaths = AppUninstaller.findAppData(for: targetURL)
                        showUninstallConfirm = true
                    }
                }

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
            MetadataSheet(
                url: targetURL,
                icon: "camera.aperture",
                title: "EXIF / Metadata",
                color: .teal,
                loader: loadExifMetadata,
                isPresented: $showExifSheet
            )
        }
        .sheet(isPresented: $showOfficeMetadataSheet) {
            MetadataSheet(
                url: targetURL,
                icon: "doc.text.magnifyingglass",
                title: "Document Info",
                color: .indigo,
                loader: loadOfficeMetadata,
                isPresented: $showOfficeMetadataSheet
            )
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
        .sheet(isPresented: $showUninstallConfirm) {
            UninstallConfirmSheet(
                appURL: targetURL,
                dataPaths: appDataPaths,
                isPresented: $showUninstallConfirm
            ) {
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

    private func loadApps(for url: URL) {
        allApps = AppSearcher.shared.appsForFile(url)
    }
}

// MARK: - Action Button (system icon)

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
            .padding(.vertical, 7)
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

// MARK: - Action Button with NSImage icon

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
            return handleFileDrop(providers: providers, appURL: app)
        }
    }
}

// MARK: - Preferred App Button

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
            return handleFileDrop(providers: providers, appURL: appURL)
        }
    }
}
