import SwiftUI
import AppKit

struct ShortcutsView: View {
    @ObservedObject var shortcutsManager = ShortcutsManager.shared
    @ObservedObject var deviceManager = iPhoneManager.shared
    @ObservedObject var manager: FileExplorerManager

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 2) {
                    SidebarSectionTitle(title: "Shortcuts", isFirst: true)

                    ForEach(shortcutsManager.allShortcuts.filter { $0.isBuiltIn }) { item in
                        ShortcutRow(item: item, manager: manager, shortcutsManager: shortcutsManager)
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
                                shortcutsManager: shortcutsManager
                            )
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
        .background(Color(red: 0xfa/255.0, green: 0xf9/255.0, blue: 0xf5/255.0))
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
            return true
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, error in
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

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            Spacer()
        }
        .padding(.leading, 38)
        .padding(.trailing, 16)
        .padding(.top, isFirst ? 6 : 22)
        .padding(.bottom, 6)
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
    let manager: FileExplorerManager
    let shortcutsManager: ShortcutsManager
    @State private var isHovered = false

    private var isSelected: Bool {
        manager.currentPath.path == item.url.path
    }

    var body: some View {
        HStack(spacing: 8) {
            if let icon = item.icon {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(.accentColor)
                    .frame(width: 26, height: 26)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                    .resizable()
                    .frame(width: 26, height: 26)
            }

            Text(formatPath(item.url.path, full: !item.isBuiltIn))
                .font(.system(size: 14))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

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
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : (isHovered ? Color.gray.opacity(0.1) : Color.clear))
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            // Switch to local browser if in iPhone mode
            if manager.currentPane == .iphone {
                iPhoneManager.shared.currentDevice = nil
                manager.currentPane = .browser
            }
            manager.navigateTo(item.url)
        }
    }
}

struct DraggableShortcutRow: View {
    let item: ShortcutItem
    let index: Int
    let manager: FileExplorerManager
    let shortcutsManager: ShortcutsManager
    @State private var isHovered = false
    @State private var isDragTarget = false

    private var isSelected: Bool {
        manager.currentPath.path == item.url.path
    }

    var body: some View {
        HStack(spacing: 8) {
            if let icon = item.icon {
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
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(formatPath(item.url.deletingLastPathComponent().path, full: true))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if isHovered {
                Button(action: { shortcutsManager.removeFolder(item.url) }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isDragTarget ? Color.accentColor.opacity(0.3) :
                      (isSelected ? Color.accentColor.opacity(0.2) :
                      (isHovered ? Color.gray.opacity(0.1) : Color.clear)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isDragTarget ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            if manager.currentPane == .iphone {
                iPhoneManager.shared.currentDevice = nil
                manager.currentPane = .browser
            }
            manager.navigateTo(item.url)
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
    let manager: FileExplorerManager
    let deviceManager: iPhoneManager
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
                .font(.system(size: 13))
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
        .padding(.vertical, 6)
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

