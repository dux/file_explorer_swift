import SwiftUI
import AppKit

struct ShortcutsView: View {
    @ObservedObject var shortcutsManager = ShortcutsManager.shared
    @ObservedObject var deviceManager = iPhoneManager.shared
    @ObservedObject var volumesManager = VolumesManager.shared
    @ObservedObject var tagManager = ColorTagManager.shared
    @ObservedObject var folderIconManager = FolderIconManager.shared
    @ObservedObject var manager: FileExplorerManager

    var body: some View {
        let builtIn = shortcutsManager.allShortcuts.filter { $0.isBuiltIn }
        let builtInCount = builtIn.count
        let pinnedCount = shortcutsManager.customFolders.count

        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 2) {
                    if #available(macOS 14.0, *) {
                        ShortcutsSectionTitle()
                    } else {
                        SidebarSectionTitle(title: "Shortcuts", isFirst: true)
                    }

                    ForEach(Array(builtIn.enumerated()), id: \.element.id) { idx, item in
                        ShortcutRow(item: item, manager: manager, shortcutsManager: shortcutsManager, flatIndex: idx)
                    }

                    if tagManager.totalCount > 0 {
                        SidebarSectionTitle(title: "Color Labels")
                        ColorTagBoxes(manager: manager, tagManager: tagManager)
                    }

                    if !deviceManager.devices.isEmpty {
                        SidebarSectionTitle(title: "Devices")

                        ForEach(deviceManager.devices) { device in
                            iPhoneRow(device: device, manager: manager, deviceManager: deviceManager)
                        }
                    }

                    if !shortcutsManager.customFolders.isEmpty {
                        SidebarSectionTitle(title: "Pinned Folders")

                        ForEach(Array(shortcutsManager.customFolders.enumerated()), id: \.element) { index, folder in
                            let item = ShortcutItem(url: folder, name: folder.lastPathComponent, isBuiltIn: false)
                        DraggableShortcutRow(
                            item: item,
                            index: index,
                            manager: manager,
                            shortcutsManager: shortcutsManager,
                            folderIconManager: folderIconManager,
                            flatIndex: builtInCount + index
                        )
                        }
                    }

                    if !volumesManager.volumes.isEmpty {
                        SidebarSectionTitle(title: "Volumes")

                        ForEach(Array(volumesManager.volumes.enumerated()), id: \.element.id) { idx, volume in
                            VolumeRow(volume: volume, manager: manager, volumesManager: volumesManager, flatIndex: builtInCount + pinnedCount + idx)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
            }
        }
        .background(Color(red: 0xfa / 255.0, green: 0xf9 / 255.0, blue: 0xf5 / 255.0))
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
            return true
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }

                DispatchQueue.main.async {
                    var isDirectory: ObjCBool = false
                    FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                    if isDirectory.boolValue {
                        shortcutsManager.addFolder(url)
                    }
                }
            }
        }
    }
}

struct SidebarSectionTitle: View {
    let title: String
    var isFirst: Bool = false
    var onTap: (() -> Void)?

    var body: some View {
        HStack {
            Text(title)
                .textStyle(.title)

            Spacer()
        }
        .padding(.leading, 38)
        .padding(.trailing, 16)
        .padding(.top, isFirst ? 6 : 22)
        .padding(.bottom, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
    }
}

@available(macOS 14.0, *)
struct ShortcutsSectionTitle: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        SidebarSectionTitle(title: "Shortcuts", isFirst: true, onTap: {
            openSettings()
            Task {
                try? await Task.sleep(nanoseconds: 100_000_000)
                NotificationCenter.default.post(name: .openSettingsTab, object: SettingsTab.shortcuts)
            }
        })
    }
}

func formatPath(_ path: String, full: Bool) -> String {
    if !full {
        return URL(fileURLWithPath: path).lastPathComponent
    }
    let homePath = FileManager.default.homeDirectoryForCurrentUser.path
    if path == homePath {
        return "~"
    } else if path.hasPrefix(homePath) {
        return "~" + path.dropFirst(homePath.count)
    }
    return path
}

struct ShortcutRow: View {
    let item: ShortcutItem
    @ObservedObject var manager: FileExplorerManager
    let shortcutsManager: ShortcutsManager
    var flatIndex: Int = -1
    @State private var isHovered = false
    @State private var isLocalHovered = false

    private var isSelected: Bool {
        manager.currentPath.path == item.url.path
    }

    private var isApplicationsRow: Bool {
        item.url.path == "/Applications"
    }

    private var isShowingLocalApps: Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return manager.currentPath.path == "\(home)/Applications"
    }

    private var isFocused: Bool {
        manager.sidebarFocused && manager.sidebarIndex == flatIndex
    }

    var body: some View {
        HStack(spacing: 8) {
            if let icon = item.icon {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(.accentColor)
                    .frame(width: 26, height: 26)
            } else {
                FolderIconView(url: item.url, size: 26)
            }

            Text(formatPath(item.url.path, full: !item.isBuiltIn))
                .textStyle(.default)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if isApplicationsRow && (isSelected || isShowingLocalApps) {
                Button(action: {
                    let localApps = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
                    if manager.currentPane == .iphone {
                        iPhoneManager.shared.currentDevice = nil
                        manager.currentPane = .browser
                    }
                    manager.navigateTo(localApps)
                    manager.selectCurrentFolder()
                }) {
                    Text("local")
                        .textStyle(.small, weight: isShowingLocalApps ? .semibold : .medium)
                        .foregroundColor(isShowingLocalApps ? .white : .secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(isShowingLocalApps ? Color.accentColor : (isLocalHovered ? Color.gray.opacity(0.15) : Color.gray.opacity(0.08)))
                        )
                }
                .buttonStyle(.plain)
                .onHover { isLocalHovered = $0 }
            }

            if !item.isBuiltIn && isHovered {
                Button(action: { shortcutsManager.removeFolder(item.url) }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill((isSelected || (isApplicationsRow && isShowingLocalApps)) ? Color.accentColor.opacity(0.2) : (isHovered ? Color.gray.opacity(0.1) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isFocused ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            // Switch to browser if in non-browser mode
            if manager.currentPane != .browser {
                if manager.currentPane == .iphone {
                    iPhoneManager.shared.currentDevice = nil
                }
                manager.currentPane = .browser
            }
            manager.navigateTo(item.url)
            manager.selectCurrentFolder()
        }
    }
}

struct DraggableShortcutRow: View {
    let item: ShortcutItem
    let index: Int
    @ObservedObject var manager: FileExplorerManager
    let shortcutsManager: ShortcutsManager
    @ObservedObject var folderIconManager: FolderIconManager
    var flatIndex: Int = -1
    @State private var isHovered = false
    @State private var isDragTarget = false
    @State private var showEmojiPicker = false

    private var isSelected: Bool {
        manager.currentPath.path == item.url.path
    }

    private var isFocused: Bool {
        manager.sidebarFocused && manager.sidebarIndex == flatIndex
    }

    private var customEmoji: String? {
        folderIconManager.emoji(for: item.url)
    }

    var body: some View {
        HStack(spacing: 8) {
            // Icon: custom emoji > SF Symbol > system icon
            if let emoji = customEmoji {
                Text(emoji)
                    .font(.system(size: 16))
                    .frame(width: 22, height: 22)
            } else if let icon = item.icon {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(.accentColor)
                    .frame(width: 22, height: 22)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                    .resizable()
                    .frame(width: 22, height: 22)
            }

            HStack(spacing: 4) {
                Text(item.url.lastPathComponent)
                    .textStyle(.default, weight: .semibold)
                    .lineLimit(1)
                Text(formatPath(item.url.deletingLastPathComponent().path, full: true))
                    .textStyle(.small)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if isHovered || showEmojiPicker {
                Button(action: { showEmojiPicker = true }) {
                    Text("Icon")
                        .textStyle(.small, weight: .medium)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showEmojiPicker, arrowEdge: .trailing) {
                    EmojiPickerView(
                        folderURL: item.url,
                        onSelect: { emoji in
                            folderIconManager.setEmoji(emoji, for: item.url)
                        },
                        onRemove: {
                            folderIconManager.removeEmoji(for: item.url)
                        },
                        onDismiss: {
                            showEmojiPicker = false
                        },
                        hasExisting: customEmoji != nil
                    )
                    .interactiveDismissDisabled()
                }

                Button(action: { shortcutsManager.removeFolder(item.url) }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isDragTarget ? Color.accentColor.opacity(0.3) :
                      (isSelected ? Color.accentColor.opacity(0.2) :
                      (isHovered ? Color.gray.opacity(0.1) : Color.clear)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke((isFocused || isDragTarget) ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            if manager.currentPane != .browser {
                if manager.currentPane == .iphone {
                    iPhoneManager.shared.currentDevice = nil
                }
                manager.currentPane = .browser
            }
            manager.navigateTo(item.url)
            manager.selectCurrentFolder()
        }
        .onDrag {
            NSItemProvider(object: String(index) as NSString)
        }
        .onDrop(of: [.text], isTargeted: $isDragTarget) { providers in
            guard let provider = providers.first else { return false }

            provider.loadItem(forTypeIdentifier: "public.text", options: nil) { data, _ in
                guard let data = data as? Data,
                      let str = String(data: data, encoding: .utf8),
                      let sourceIndex = Int(str),
                      sourceIndex != index else { return }

                DispatchQueue.main.async {
                    let dest = sourceIndex < index ? index + 1 : index
                    shortcutsManager.moveFolder(from: IndexSet(integer: sourceIndex), to: dest)
                }
            }
            return true
        }
    }
}

struct iPhoneRow: View {
    let device: iPhoneDevice
    @ObservedObject var manager: FileExplorerManager
    @ObservedObject var deviceManager: iPhoneManager
    @State private var isHovered = false
    @State private var isLoading = false

    private var isSelected: Bool {
        deviceManager.currentDevice?.id == device.id
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "iphone")
                .font(.system(size: 14))
                .foregroundColor(.pink)
                .frame(width: 20)

            Text(device.name)
                .textStyle(.default, weight: .semibold)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if isLoading || deviceManager.isLoadingFiles && isSelected {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 16, height: 16)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : (isHovered ? Color.gray.opacity(0.1) : Color.clear))
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            Task {
                isLoading = true
                await deviceManager.selectDevice(device)
                manager.currentPane = .iphone
                isLoading = false
            }
        }
    }
}

struct VolumeRow: View {
    let volume: VolumeInfo
    @ObservedObject var manager: FileExplorerManager
    let volumesManager: VolumesManager
    var flatIndex: Int = -1
    @State private var isHovered = false

    private var isSelected: Bool {
        manager.currentPath.path.hasPrefix(volume.url.path)
    }

    private var isFocused: Bool {
        manager.sidebarFocused && manager.sidebarIndex == flatIndex
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: volume.icon)
                .font(.system(size: 14))
                .foregroundColor(Color(volume.iconColor))
                .frame(width: 20)

            Text(volume.name)
                .textStyle(.default, weight: .semibold)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if !volume.capacityText.isEmpty {
                Text(volume.capacityText)
                    .textStyle(.small)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            if isHovered && volume.isEjectable {
                Button(action: { volumesManager.eject(volume) }) {
                    Image(systemName: "eject.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : (isHovered ? Color.gray.opacity(0.1) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isFocused ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            if manager.currentPane != .browser {
                if manager.currentPane == .iphone {
                    iPhoneManager.shared.currentDevice = nil
                }
                manager.currentPane = .browser
            }
            manager.navigateTo(volume.url)
            manager.selectCurrentFolder()
        }
    }
}

struct ColorTagBoxes: View {
    @ObservedObject var manager: FileExplorerManager
    @ObservedObject var tagManager: ColorTagManager

    var body: some View {
        HStack(spacing: 5) {
            ForEach(TagColor.allCases) { color in
                ColorTagBox(
                    color: color,
                    count: tagManager.count(for: color),
                    isActive: isActive(color),
                    manager: manager
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
    }

    private func isActive(_ color: TagColor) -> Bool {
        if case .colorTag(let c) = manager.currentPane {
            return c == color
        }
        return false
    }
}

struct ColorTagBox: View {
    let color: TagColor
    let count: Int
    let isActive: Bool
    @ObservedObject var manager: FileExplorerManager
    @State private var isHovered = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(color.color.opacity(isActive ? 1.0 : (isHovered ? 0.85 : 0.7)))
                .shadow(color: isActive ? color.color.opacity(0.4) : .clear, radius: 3, y: 1)

            Text("\(count)")
                .textStyle(.buttons, weight: .bold)
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            manager.listCursorIndex = -1
            manager.currentPane = .colorTag(color)
        }
    }
}
