import SwiftUI
import AppKit

// MARK: - Context Menu Manager

@MainActor
class ContextMenuManager: ObservableObject {
    static let shared = ContextMenuManager()

    @Published var isShowing = false
    @Published var url: URL?
    @Published var isDirectory = false
    @Published var position: CGPoint = .zero
    @Published var focusedIndex: Int = 0
    var itemCount: Int = 0
    var itemActions: [() -> Void] = []

    func show(url: URL, isDirectory: Bool, at position: CGPoint) {
        self.url = url
        self.isDirectory = isDirectory
        self.position = position
        self.focusedIndex = 0
        self.itemCount = 0
        self.itemActions = []
        self.isShowing = true
    }

    func dismiss() {
        isShowing = false
        focusedIndex = 0
        itemCount = 0
        itemActions = []
    }

    func moveFocus(_ delta: Int) {
        guard itemCount > 0 else { return }
        focusedIndex = (focusedIndex + delta + itemCount) % itemCount
    }

    func activateFocused() {
        guard focusedIndex >= 0 && focusedIndex < itemActions.count else { return }
        itemActions[focusedIndex]()
    }
}

// MARK: - Context Menu Overlay (add to ContentView ZStack)

struct CustomContextMenuOverlay: View {
    @ObservedObject var contextMenu = ContextMenuManager.shared
    @ObservedObject var manager: FileExplorerManager
    @ObservedObject var tagManager = ColorTagManager.shared
    @State private var showingDetails = false
    @State private var menuSize: CGSize = .zero

    var body: some View {
        if contextMenu.isShowing, let url = contextMenu.url {
            GeometryReader { geo in
                let clamped = clampedPosition(in: geo.size)

                // Dismiss backdrop
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { contextMenu.dismiss() }

                // Menu content
                CustomContextMenuContent(
                    url: url,
                    isDirectory: contextMenu.isDirectory,
                    manager: manager,
                    tagManager: tagManager,
                    showingDetails: $showingDetails,
                    onDismiss: { contextMenu.dismiss() }
                )
                .fixedSize()
                .background(GeometryReader { menuGeo in
                    Color.clear.onAppear { menuSize = menuGeo.size }
                })
                .position(x: clamped.x + menuSize.width / 2, y: clamped.y + menuSize.height / 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .sheet(isPresented: $showingDetails) {
                FileDetailsView(url: contextMenu.url ?? url, isDirectory: contextMenu.isDirectory)
            }
        }
    }

    private func clampedPosition(in containerSize: CGSize) -> CGPoint {
        let margin: CGFloat = 8
        var x = contextMenu.position.x
        var y = contextMenu.position.y

        // Clamp right
        if x + menuSize.width + margin > containerSize.width {
            x = containerSize.width - menuSize.width - margin
        }
        // Clamp left
        if x < margin { x = margin }
        // Clamp bottom
        if y + menuSize.height + margin > containerSize.height {
            y = containerSize.height - menuSize.height - margin
        }
        // Clamp top
        if y < margin { y = margin }

        return CGPoint(x: x, y: y)
    }
}

// MARK: - Context Menu Content

private struct CustomContextMenuContent: View {
    let url: URL
    let isDirectory: Bool
    @ObservedObject var manager: FileExplorerManager
    @ObservedObject var tagManager: ColorTagManager
    @ObservedObject var contextMenu = ContextMenuManager.shared
    @Binding var showingDetails: Bool
    let onDismiss: () -> Void

    private var isArchive: Bool {
        ["zip", "tar", "tgz", "gz", "bz2", "xz", "rar", "7z"].contains(url.pathExtension.lowercased())
    }

    private var isApp: Bool {
        url.pathExtension.lowercased() == "app" && isDirectory
    }

    private var isHiddenFile: Bool {
        url.lastPathComponent.hasPrefix(".")
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

    private var menuItems: [MenuItem] {
        var items: [MenuItem] = []
        items.append(MenuItem(icon: "info.circle", label: "View Details", isDestructive: false, isColor: false, tagColor: nil, isTagged: false) {
            showingDetails = true
            onDismiss()
        })
        items.append(MenuItem(
            icon: manager.isInSelection(url) ? "minus.circle" : "checkmark.circle",
            label: manager.isInSelection(url) ? "Remove from Selection" : "Add to Selection",
            isDestructive: false, isColor: false, tagColor: nil, isTagged: false
        ) {
            manager.toggleFileSelection(url)
            onDismiss()
        })
        items.append(MenuItem(icon: "doc.on.clipboard", label: "Copy Path", isDestructive: false, isColor: false, tagColor: nil, isTagged: false) {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(url.path, forType: .string)
            onDismiss()
        })
        items.append(MenuItem(icon: "pencil", label: "Rename", isDestructive: false, isColor: false, tagColor: nil, isTagged: false) {
            manager.selectedItem = url
            manager.startRename()
            onDismiss()
        })
        items.append(MenuItem(icon: "folder", label: "Show in Finder", isDestructive: false, isColor: false, tagColor: nil, isTagged: false) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            onDismiss()
        })
        items.append(MenuItem(icon: "doc.on.doc", label: "Duplicate", isDestructive: false, isColor: false, tagColor: nil, isTagged: false) {
            manager.duplicateFile(url)
            onDismiss()
        })
        items.append(MenuItem(icon: "doc.zipper", label: "Add to Zip", isDestructive: false, isColor: false, tagColor: nil, isTagged: false) {
            manager.addToZip(url)
            onDismiss()
        })
        if isArchive {
            items.append(MenuItem(icon: "arrow.down.doc", label: "Extract to folder", isDestructive: false, isColor: false, tagColor: nil, isTagged: false) {
                manager.extractArchive(url)
                onDismiss()
            })
        }
        if isApp {
            items.append(MenuItem(icon: "checkmark.shield", label: "Enable unsafe app", isDestructive: false, isColor: false, tagColor: nil, isTagged: false) {
                manager.enableUnsafeApp(url)
                onDismiss()
            })
        }
        items.append(MenuItem(
            icon: isHiddenFile ? "eye" : "eye.slash",
            label: isHiddenFile ? "Make Visible" : "Make Hidden",
            isDestructive: false, isColor: false, tagColor: nil, isTagged: false
        ) {
            manager.toggleHidden(url)
            onDismiss()
        })
        items.append(MenuItem(icon: "trash", label: "Move to Trash", isDestructive: true, isColor: false, tagColor: nil, isTagged: false) {
            manager.moveToTrash(url)
            onDismiss()
        })
        for color in TagColor.allCases {
            let tagged = tagManager.isTagged(url, color: color)
            items.append(MenuItem(icon: "", label: color.label, isDestructive: false, isColor: true, tagColor: color, isTagged: tagged) {
                tagManager.toggleTag(url, color: color)
                onDismiss()
            })
        }
        let currentColors = tagManager.colorsForFile(url)
        if !currentColors.isEmpty {
            items.append(MenuItem(icon: "xmark.circle", label: "Remove All Labels", isDestructive: false, isColor: false, tagColor: nil, isTagged: false) {
                tagManager.untagFile(url)
                onDismiss()
            })
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
                        FolderIconView(url: url, size: 18, selected: false)
                    } else {
                        Image(nsImage: IconProvider.shared.icon(for: url, isDirectory: false, selected: false))
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
        let needsDivider = index == 5 || index == sectionBreak2(items) || index == sectionBreak3(items)
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

// MARK: - View Extension

extension View {
    func customContextMenu(url: URL, isDirectory: Bool) -> some View {
        self.overlay(
            RightClickableArea(url: url, isDirectory: isDirectory)
        )
    }
}
