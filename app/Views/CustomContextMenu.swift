import SwiftUI
import AppKit

// MARK: - Context Menu Manager

@MainActor
class ContextMenuManager: ObservableObject {
    static let shared = ContextMenuManager()

    @Published var isShowing = false
    @Published var url: URL?
    @Published var isDirectory = false
    @Published var isFolderMenu = false
    @Published var position: CGPoint = .zero
    @Published var focusedIndex: Int = 0
    @Published var showDetails = false
    @Published var showEmojiPicker = false
    var detailsURL: URL?
    var detailsIsDirectory = false
    var emojiPickerURL: URL?
    var itemCount: Int = 0
    var itemActions: [() -> Void] = []
    var pendingAction: (() -> Void)?

    func show(url: URL, isDirectory: Bool, at position: CGPoint, keyboardTriggered: Bool = false) {
        self.url = url
        self.isDirectory = isDirectory
        self.isFolderMenu = false
        self.position = position
        self.focusedIndex = keyboardTriggered ? 0 : -1
        self.itemCount = 0
        self.itemActions = []
        self.isShowing = true
    }

    func showFolderMenu(url: URL, at position: CGPoint) {
        self.url = url
        self.isDirectory = true
        self.isFolderMenu = true
        self.position = position
        self.focusedIndex = -1
        self.itemCount = 0
        self.itemActions = []
        self.isShowing = true
    }

    func dismiss() {
        isShowing = false
        isFolderMenu = false
        focusedIndex = 0
        itemCount = 0
        itemActions = []
    }

    func dismissAndRun(_ action: @escaping () -> Void) {
        pendingAction = action
        dismiss()
    }

    func moveFocus(_ delta: Int) {
        guard itemCount > 0 else { return }
        if focusedIndex < 0 {
            focusedIndex = delta > 0 ? 0 : itemCount - 1
        } else {
            focusedIndex = (focusedIndex + delta + itemCount) % itemCount
        }
    }

    func activateFocused() {
        guard focusedIndex >= 0 && focusedIndex < itemActions.count else { return }
        let action = itemActions[focusedIndex]
        dismissAndRun(action)
    }
}

// MARK: - Context Menu Overlay (add to ContentView ZStack)

struct CustomContextMenuOverlay: View {
    @ObservedObject var contextMenu = ContextMenuManager.shared
    @ObservedObject var manager: FileExplorerManager
    @ObservedObject var tagManager = ColorTagManager.shared
    var body: some View {
        ZStack {
            if contextMenu.isShowing, let url = contextMenu.url {
                GeometryReader { geo in
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { contextMenu.dismiss() }

                    if contextMenu.isFolderMenu {
                        FolderContextMenuContent(
                            url: url,
                            manager: manager
                        )
                        .fixedSize()
                        .position(x: geo.size.width / 2, y: geo.size.height * 0.4)
                    } else {
                        CustomContextMenuContent(
                            url: url,
                            isDirectory: contextMenu.isDirectory,
                            manager: manager,
                            tagManager: tagManager
                        )
                        .fixedSize()
                        .position(x: geo.size.width / 2, y: geo.size.height * 0.4)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: contextMenu.isShowing) { showing in
            if !showing, let action = contextMenu.pendingAction {
                contextMenu.pendingAction = nil
                DispatchQueue.main.async { action() }
            }
        }
        .sheet(isPresented: $contextMenu.showDetails) {
            if let url = contextMenu.detailsURL {
                FileDetailsView(url: url, isDirectory: contextMenu.detailsIsDirectory)
            }
        }
        .sheet(isPresented: $contextMenu.showEmojiPicker) {
            if let url = contextMenu.emojiPickerURL {
                EmojiPickerView(
                    folderURL: url,
                    onSelect: { emoji in
                        FolderIconManager.shared.setEmoji(emoji, for: url)
                    },
                    onRemove: {
                        FolderIconManager.shared.removeEmoji(for: url)
                    },
                    onDismiss: { contextMenu.showEmojiPicker = false },
                    hasExisting: FolderIconManager.shared.emoji(for: url) != nil
                )
                .interactiveDismissDisabled()
            }
        }
    }
}

// MARK: - Context Menu Content

private struct CustomContextMenuContent: View {
    let url: URL
    let isDirectory: Bool
    @ObservedObject var manager: FileExplorerManager
    @ObservedObject var tagManager: ColorTagManager
    @ObservedObject var contextMenu = ContextMenuManager.shared

    private var isArchive: Bool {
        ["zip", "tar", "tgz", "gz", "bz2", "xz", "rar", "7z"].contains(url.pathExtension.lowercased())
    }

    private var isApp: Bool {
        url.pathExtension.lowercased() == "app" && isDirectory
    }

    private var isHiddenFile: Bool {
        let resourceValues = try? url.resourceValues(forKeys: [.isHiddenKey])
        return resourceValues?.isHidden ?? url.lastPathComponent.hasPrefix(".")
    }

    private struct MenuItem {
        let icon: String
        let label: String
        let isDestructive: Bool
        let isColor: Bool
        let tagColor: TagColor?
        let isTagged: Bool
        let action: () -> Void
    }

    private func act(_ action: @escaping () -> Void) -> () -> Void {
        { contextMenu.dismissAndRun(action) }
    }

    @ObservedObject private var selection = SelectionManager.shared

    private var menuItems: [MenuItem] {
        var items: [MenuItem] = []
        if isDirectory && !selection.localItems.isEmpty {
            let count = selection.localItems.count
            items.append(MenuItem(icon: "doc.on.doc", label: "Copy \(count) here", isDestructive: false, isColor: false, tagColor: nil, isTagged: false, action: act { [url] in
                let copied = SelectionManager.shared.copyLocalItems(to: url)
                SelectionManager.shared.clear()
                ToastManager.shared.show("Copied \(copied) file(s)")
                manager.refresh()
            }))
            items.append(MenuItem(icon: "folder", label: "Move \(count) here", isDestructive: false, isColor: false, tagColor: nil, isTagged: false, action: act { [url] in
                let moved = SelectionManager.shared.moveLocalItems(to: url)
                SelectionManager.shared.clear()
                ToastManager.shared.show("Moved \(moved) file(s)")
                manager.refresh()
            }))
        }
        items.append(MenuItem(icon: "info.circle", label: "View Details", isDestructive: false, isColor: false, tagColor: nil, isTagged: false, action: act { [url, isDirectory] in
            contextMenu.detailsURL = url
            contextMenu.detailsIsDirectory = isDirectory
            contextMenu.showDetails = true
        }))
        items.append(MenuItem(
            icon: manager.isInSelection(url) ? "minus.circle" : "checkmark.circle",
            label: manager.isInSelection(url) ? "Remove from Selection" : "Add to Selection",
            isDestructive: false, isColor: false, tagColor: nil, isTagged: false, action: act {
                manager.toggleFileSelection(url)
            }
        ))
        if isDirectory && !isApp {
            items.append(MenuItem(icon: "face.smiling", label: "Assign Icon", isDestructive: false, isColor: false, tagColor: nil, isTagged: false, action: act { [url] in
                contextMenu.emojiPickerURL = url
                contextMenu.showEmojiPicker = true
            }))
        }
        items.append(MenuItem(icon: "doc.on.clipboard", label: "Copy Path", isDestructive: false, isColor: false, tagColor: nil, isTagged: false, action: act {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(url.path, forType: .string)
            ToastManager.shared.show("Path copied to clipboard")
        }))
        items.append(MenuItem(icon: "pencil", label: "Rename", isDestructive: false, isColor: false, tagColor: nil, isTagged: false, action: act {
            manager.selectedItem = url
            manager.startRename()
        }))
        items.append(MenuItem(icon: "folder", label: "Show in Finder", isDestructive: false, isColor: false, tagColor: nil, isTagged: false, action: act {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }))
        items.append(MenuItem(icon: "doc.on.doc", label: "Duplicate", isDestructive: false, isColor: false, tagColor: nil, isTagged: false, action: act {
            manager.duplicateFile(url)
        }))
        items.append(MenuItem(icon: "doc.zipper", label: "Add to Zip", isDestructive: false, isColor: false, tagColor: nil, isTagged: false, action: act {
            manager.addToZip(url)
        }))
        if isArchive {
            items.append(MenuItem(icon: "arrow.down.doc", label: "Extract to folder", isDestructive: false, isColor: false, tagColor: nil, isTagged: false, action: act {
                manager.extractArchive(url)
            }))
        }
        if isApp {
            items.append(MenuItem(icon: "checkmark.shield", label: "Enable unsafe app", isDestructive: false, isColor: false, tagColor: nil, isTagged: false, action: act {
                manager.enableUnsafeApp(url)
            }))
        }
        items.append(MenuItem(
            icon: isHiddenFile ? "eye" : "eye.slash",
            label: isHiddenFile ? "Make Visible" : "Make Hidden",
            isDestructive: false, isColor: false, tagColor: nil, isTagged: false, action: act {
                manager.toggleHidden(url)
            }
        ))
        items.append(MenuItem(icon: "trash", label: "Move to Trash", isDestructive: true, isColor: false, tagColor: nil, isTagged: false, action: act {
            manager.moveToTrash(url)
        }))
        for color in TagColor.allCases {
            let tagged = tagManager.isTagged(url, color: color)
            items.append(MenuItem(icon: "", label: color.label, isDestructive: false, isColor: true, tagColor: color, isTagged: tagged, action: act {
                tagManager.toggleTag(url, color: color)
            }))
        }
        let currentColors = tagManager.colorsForFile(url)
        if !currentColors.isEmpty {
            items.append(MenuItem(icon: "xmark.circle", label: "Remove All Labels", isDestructive: false, isColor: false, tagColor: nil, isTagged: false, action: act {
                tagManager.untagFile(url)
            }))
        }
        return items
    }

    var body: some View {
        let items = menuItems
        VStack(alignment: .leading, spacing: 0) {
            // Title: file icon + name
            HStack(alignment: .center, spacing: 10) {
                Group {
                    if isDirectory {
                        FolderIconView(url: url, size: 18)
                    } else {
                        Image(nsImage: IconProvider.shared.icon(for: url, isDirectory: false))
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 18, height: 18)
                    }
                }
                .frame(width: 18, height: 18)
                Text(url.lastPathComponent)
                    .textStyle(.default, weight: .semibold)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 6)

            Divider()
                .padding(.horizontal, 8)
                .padding(.bottom, 4)

            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                menuRowView(item: item, index: index, items: items)
            }
        }
        .padding(.vertical, 6)
        .frame(width: 220)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: 0xfa / 255.0, green: 0xf9 / 255.0, blue: 0xf5 / 255.0))
                .shadow(color: .black.opacity(0.35), radius: 24, x: 0, y: 10)
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(red: 0.8, green: 0.8, blue: 0.8), lineWidth: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onAppear {
            contextMenu.itemCount = items.count
            contextMenu.itemActions = items.map { $0.action }
        }
    }

    @ViewBuilder
    private func menuRowView(item: MenuItem, index: Int, items: [MenuItem]) -> some View {
        let needsDivider = index == sectionBreakAfterSelection(items) || index == sectionBreakAfterCopyPath(items) || index == sectionBreak2(items) || index == sectionBreak3(items)
        let focused = contextMenu.focusedIndex == index
        if needsDivider {
            ContextMenuDivider()
        }
        if item.isColor, let tagColor = item.tagColor {
            ContextMenuColorRow(color: tagColor, isTagged: item.isTagged, isFocused: focused, action: item.action)
        } else {
            ContextMenuRow(icon: item.icon, label: item.label, isDestructive: item.isDestructive, isFocused: focused, action: item.action)
        }
    }

    private func sectionBreakAfterSelection(_ items: [MenuItem]) -> Int {
        guard let idx = items.firstIndex(where: { $0.label == "View Details" }) else { return -1 }
        return idx > 0 ? idx : -1
    }

    private func sectionBreakAfterCopyPath(_ items: [MenuItem]) -> Int {
        guard let idx = items.firstIndex(where: { $0.label == "Copy Path" }) else { return -1 }
        return idx + 1
    }

    private func sectionBreak2(_ items: [MenuItem]) -> Int {
        items.firstIndex(where: { $0.label == "Move to Trash" }) ?? 0
    }

    private func sectionBreak3(_ items: [MenuItem]) -> Int {
        items.firstIndex(where: { $0.isColor }) ?? 0
    }
}

// MARK: - Menu Row

private struct ContextMenuRow: View {
    let icon: String
    let label: String
    var isDestructive: Bool = false
    var isFocused: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    private var isHighlighted: Bool { isHovered || isFocused }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .frame(width: 18, height: 18)
                    .foregroundColor(foregroundColor(forIcon: true))
                Text(label)
                    .textStyle(.default)
                    .foregroundColor(foregroundColor(forIcon: false))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(isHighlighted ? Color.accentColor : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private func foregroundColor(forIcon: Bool) -> Color {
        if isHighlighted { return .white }
        if isDestructive { return .red }
        return forIcon ? .secondary : .primary
    }
}

// MARK: - Color Tag Row

private struct ContextMenuColorRow: View {
    let color: TagColor
    let isTagged: Bool
    var isFocused: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    private var isHighlighted: Bool { isHovered || isFocused }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(color.color)
                        .frame(width: 12, height: 12)
                    if isTagged {
                        Image(systemName: "checkmark")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .frame(width: 18, height: 18)
                Text(color.label)
                    .textStyle(.default)
                    .foregroundColor(isHighlighted ? .white : .primary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(isHighlighted ? Color.accentColor : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Menu Divider

private struct ContextMenuDivider: View {
    var body: some View {
        Divider()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
    }
}

// MARK: - Folder Context Menu Content

private struct FolderContextMenuContent: View {
    let url: URL
    @ObservedObject var manager: FileExplorerManager
    @ObservedObject var contextMenu = ContextMenuManager.shared

    private func act(_ action: @escaping () -> Void) -> () -> Void {
        { contextMenu.dismissAndRun(action) }
    }

    private struct MenuItem {
        let icon: String
        let label: String
        let action: () -> Void
    }

    @ObservedObject private var selection = SelectionManager.shared

    private var menuItems: [MenuItem] {
        var items: [MenuItem] = []
        if !selection.localItems.isEmpty {
            let count = selection.localItems.count
            items.append(MenuItem(icon: "doc.on.doc", label: "Copy \(count) here", action: act { [url] in
                let copied = SelectionManager.shared.copyLocalItems(to: url)
                SelectionManager.shared.clear()
                ToastManager.shared.show("Copied \(copied) file(s)")
                manager.refresh()
            }))
            items.append(MenuItem(icon: "folder", label: "Move \(count) here", action: act { [url] in
                let moved = SelectionManager.shared.moveLocalItems(to: url)
                SelectionManager.shared.clear()
                ToastManager.shared.show("Moved \(moved) file(s)")
                manager.refresh()
            }))
        }
        items.append(MenuItem(icon: "info.circle", label: "View Details", action: act { [url] in
            contextMenu.detailsURL = url
            contextMenu.detailsIsDirectory = true
            contextMenu.showDetails = true
        }))
        items.append(MenuItem(icon: "face.smiling", label: "Assign Icon", action: act { [url] in
            contextMenu.emojiPickerURL = url
            contextMenu.showEmojiPicker = true
        }))
        items.append(MenuItem(icon: "doc.on.clipboard", label: "Copy Path", action: act { [url] in
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(url.path, forType: .string)
            ToastManager.shared.show("Path copied to clipboard")
        }))
        items.append(MenuItem(icon: "folder.badge.plus", label: "Create Folder", action: act {
            manager.createNewFolder()
        }))
        items.append(MenuItem(icon: "doc.badge.plus", label: "Create File", action: act {
            manager.newFileName = "untitled.txt"
            manager.showNewFileDialog = true
        }))
        return items
    }

    var body: some View {
        let items = menuItems
        VStack(alignment: .leading, spacing: 0) {
            // Title: folder icon + name
            HStack(alignment: .center, spacing: 10) {
                FolderIconView(url: url, size: 18)
                    .frame(width: 18, height: 18)
                Text(url.lastPathComponent)
                    .textStyle(.default, weight: .semibold)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 6)

            Divider()
                .padding(.horizontal, 8)
                .padding(.bottom, 4)

            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if item.label == "View Details" && index > 0 {
                    ContextMenuDivider()
                }
                let focused = contextMenu.focusedIndex == index
                ContextMenuRow(icon: item.icon, label: item.label, isFocused: focused, action: item.action)
            }
        }
        .padding(.vertical, 6)
        .frame(width: 220)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: 0xfa / 255.0, green: 0xf9 / 255.0, blue: 0xf5 / 255.0))
                .shadow(color: .black.opacity(0.35), radius: 24, x: 0, y: 10)
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(red: 0.8, green: 0.8, blue: 0.8), lineWidth: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onAppear {
            contextMenu.itemCount = items.count
            contextMenu.itemActions = items.map { $0.action }
        }
    }
}

// MARK: - Right-Click Gesture (NSViewRepresentable, transparent to other events)

struct RightClickableArea: NSViewRepresentable {
    let url: URL
    let isDirectory: Bool

    func makeNSView(context: Context) -> RightClickNSView {
        let view = RightClickNSView()
        view.url = url
        view.isDirectory = isDirectory
        return view
    }

    func updateNSView(_ nsView: RightClickNSView, context: Context) {
        nsView.url = url
        nsView.isDirectory = isDirectory
    }

    class RightClickNSView: NSView {
        var url: URL?
        var isDirectory: Bool = false

        override func rightMouseDown(with event: NSEvent) {
            guard let url = url,
                  let window = self.window,
                  let contentView = window.contentView else { return }
            let windowPoint = event.locationInWindow
            let contentHeight = contentView.frame.height
            let flippedY = contentHeight - windowPoint.y
            // Menu position: nudge 50px right, 200px up from click
            let position = CGPoint(
                x: windowPoint.x + 50,
                y: flippedY - 200
            )
            Task { @MainActor in
                ContextMenuManager.shared.show(url: url, isDirectory: isDirectory, at: position)
            }
        }

        // Pass all non-right-click events through to SwiftUI views underneath
        override func hitTest(_ point: NSPoint) -> NSView? {
            // Check if this is being called during a right-click
            // by looking at the current event
            if let event = NSApp.currentEvent, event.type == .rightMouseDown {
                return super.hitTest(point)
            }
            return nil
        }
    }
}

// MARK: - Folder Background Right-Click

struct FolderBackgroundRightClickArea: NSViewRepresentable {
    let folderURL: URL

    func makeNSView(context: Context) -> FolderRightClickNSView {
        let view = FolderRightClickNSView()
        view.folderURL = folderURL
        return view
    }

    func updateNSView(_ nsView: FolderRightClickNSView, context: Context) {
        nsView.folderURL = folderURL
    }

    class FolderRightClickNSView: NSView {
        var folderURL: URL?

        override func rightMouseDown(with event: NSEvent) {
            guard let url = folderURL,
                  let window = self.window,
                  let contentView = window.contentView else { return }
            let windowPoint = event.locationInWindow
            let contentHeight = contentView.frame.height
            let flippedY = contentHeight - windowPoint.y
            let position = CGPoint(
                x: windowPoint.x + 50,
                y: flippedY - 200
            )
            Task { @MainActor in
                ContextMenuManager.shared.showFolderMenu(url: url, at: position)
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            if let event = NSApp.currentEvent, event.type == .rightMouseDown {
                return super.hitTest(point)
            }
            return nil
        }
    }
}

// MARK: - View Extension

extension View {
    func customContextMenu(url: URL, isDirectory: Bool) -> some View {
        self.overlay(
            RightClickableArea(url: url, isDirectory: isDirectory)
        )
    }

    func folderBackgroundContextMenu(url: URL) -> some View {
        self.overlay(
            FolderBackgroundRightClickArea(folderURL: url)
        )
    }
}
