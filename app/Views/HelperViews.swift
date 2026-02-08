import SwiftUI
import AppKit

// MARK: - Global Input Style

struct StyledInput: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textStyle(.default)
            .padding(2)
            .textFieldStyle(.roundedBorder)
    }
}

extension View {
    func styledInput() -> some View {
        modifier(StyledInput())
    }
}

// MARK: - Reusable File List Row (one-liner: icon + name + path)

struct FileListRow: View {
    let url: URL
    let isDirectory: Bool
    let exists: Bool
    let parentPath: String
    let isSelected: Bool
    var showRemove: Bool = false
    var onRemove: (() -> Void)? = nil

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            // Icon
            if !exists {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 18))
                    .foregroundColor(.secondary.opacity(0.5))
                    .frame(width: 22, height: 22)
            } else if isDirectory {
                FolderIconView(url: url, size: 22)
            } else {
                Image(nsImage: IconProvider.shared.icon(for: url, isDirectory: false))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 22, height: 22)
            }

            // Name
            Text(url.lastPathComponent)
                .textStyle(.default)
                .foregroundColor(exists ? .primary : .secondary.opacity(0.5))
                .strikethrough(!exists)
                .lineLimit(1)

            // Parent path
            Text(parentPath)
                .textStyle(.small)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.head)

            Spacer(minLength: 4)

            if showRemove && isHovered {
                if let onRemove {
                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle.fill")
                            .textStyle(.small)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(
            isSelected ? Color.accentColor.opacity(0.2) :
            isHovered ? Color.gray.opacity(0.08) : Color.clear
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}

// MARK: - File Details

struct FileDetailsView: View {
    let url: URL
    let isDirectory: Bool
    @Environment(\.dismiss) var dismiss
    @State private var fileSize: String = "Calculating..."
    @State private var itemCount: Int? = nil
    @State private var cachedAttributes: [FileAttributeKey: Any]?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: isDirectory ? "folder.fill" : "doc.fill")
                    .font(.system(size: 32))
                    .foregroundColor(isDirectory ? Color(red: 0.35, green: 0.67, blue: 0.95) : .secondary)

                Text(url.lastPathComponent)
                    .textStyle(.default, weight: .semibold)
                    .lineLimit(2)

                Spacer()
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                DetailRow(label: "Kind", value: isDirectory ? "Folder" : fileKind)
                DetailRow(label: "Size", value: fileSize)
                if let count = itemCount {
                    DetailRow(label: "Contains", value: "\(count) items")
                }
                DetailRow(label: "Location", value: url.deletingLastPathComponent().path)
                if let created = cachedAttributes?[.creationDate] as? Date {
                    DetailRow(label: "Created", value: formatDateShort(created))
                }
                if let modified = cachedAttributes?[.modificationDate] as? Date {
                    DetailRow(label: "Modified", value: formatDateShort(modified))
                }
                if let permissions = cachedAttributes?[.posixPermissions] as? Int {
                    DetailRow(label: "Permissions", value: String(format: "%o", permissions))
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 400, height: 350)
        .onAppear {
            cachedAttributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            calculateSize()
        }
    }

    private var fileKind: String {
        let ext = url.pathExtension.lowercased()
        if ext.isEmpty { return "File" }
        return "\(ext.uppercased()) file"
    }

    private func calculateSize() {
        calculateFileSize(url: url, isDirectory: isDirectory) { sizeStr, count in
            fileSize = sizeStr
            itemCount = count
        }
    }
}

// MARK: - File Item Dialog (ENTER key dialog)

struct FileItemDialog: View {
    @ObservedObject var manager: FileExplorerManager
    @ObservedObject var selection = SelectionManager.shared
    let url: URL
    let isDirectory: Bool
    @Environment(\.dismiss) var dismiss
    @State private var renameText: String = ""
    @State private var fileSize: String = "Calculating..."
    @State private var itemCount: Int? = nil
    @State private var cachedAttributes: [FileAttributeKey: Any]?
    @State private var isRenaming: Bool = false
    @FocusState private var renameFieldFocused: Bool

    private var isInSelection: Bool {
        let _ = selection.version
        return selection.items.contains { $0.localURL == url }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with icon and name
            HStack(spacing: 10) {
                if isDirectory {
                    FolderIconView(url: url, size: 36)
                } else {
                    Image(nsImage: IconProvider.shared.icon(for: url, isDirectory: false))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 36, height: 36)
                }

                if isRenaming {
                    RenameTextField(text: $renameText, onCommit: {
                        performRename()
                    }, onCancel: {
                        isRenaming = false
                        renameText = url.lastPathComponent
                    })
                    .frame(height: 22)
                } else {
                    Text(url.lastPathComponent)
                        .textStyle(.default, weight: .semibold)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()

            // File details
            VStack(alignment: .leading, spacing: 8) {
                DetailRow(label: "Kind", value: isDirectory ? "Folder" : fileKind)
                DetailRow(label: "Size", value: fileSize)
                if let count = itemCount {
                    DetailRow(label: "Contains", value: "\(count) items")
                }
                DetailRow(label: "Location", value: url.deletingLastPathComponent().path)
                if let modified = cachedAttributes?[.modificationDate] as? Date {
                    DetailRow(label: "Modified", value: formatDateShort(modified))
                }
                if let created = cachedAttributes?[.creationDate] as? Date {
                    DetailRow(label: "Created", value: formatDateShort(created))
                }
                if let permissions = cachedAttributes?[.posixPermissions] as? Int {
                    DetailRow(label: "Permissions", value: String(format: "%o", permissions))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            // Actions
            VStack(spacing: 2) {
                // Rename
                Button(action: {
                    if isRenaming {
                        performRename()
                    } else {
                        renameText = url.lastPathComponent
                        isRenaming = true
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: isRenaming ? "checkmark.circle" : "pencil")
                            .frame(width: 16)
                        Text(isRenaming ? "Confirm Rename" : "Rename")
                        Spacer()
                        if !isRenaming {
                            Text("R")
                                .textStyle(.small)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15))
                                .cornerRadius(3)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Toggle selection
                Button(action: {
                    if let fileItem = FileItem.fromLocal(url) {
                        selection.toggle(fileItem)
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: isInSelection ? "checkmark.circle.fill" : "circle")
                            .frame(width: 16)
                            .foregroundColor(isInSelection ? .green : .primary)
                        Text(isInSelection ? "Remove from Selection" : "Add to Selection")
                        Spacer()
                        Text("Space")
                            .textStyle(.small)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15))
                            .cornerRadius(3)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Add to Zip
                Button(action: {
                    manager.addToZip(url)
                    dismiss()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.zipper")
                            .frame(width: 16)
                        Text("Add to Zip")
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Duplicate
                Button(action: {
                    manager.duplicateFile(url)
                    dismiss()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.on.doc")
                            .frame(width: 16)
                        Text("Duplicate")
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Divider()
                    .padding(.horizontal, 12)

                // Move to Trash
                Button(action: {
                    manager.moveToTrash(url)
                    dismiss()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "trash")
                            .frame(width: 16)
                            .foregroundColor(.red)
                        Text("Move to Trash")
                            .foregroundColor(.red)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 6)

            Divider()

            // Bottom bar
            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 420)
        .onAppear {
            renameText = url.lastPathComponent
            cachedAttributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            calculateSize()
        }
    }

    private var fileKind: String {
        let ext = url.pathExtension.lowercased()
        if ext.isEmpty { return isDirectory ? "Folder" : "File" }
        return "\(ext.uppercased()) file"
    }

    private func performRename() {
        let newName = renameText.trimmingCharacters(in: .whitespaces)
        guard !newName.isEmpty, newName != url.lastPathComponent else {
            isRenaming = false
            renameText = url.lastPathComponent
            return
        }

        let newURL = url.deletingLastPathComponent().appendingPathComponent(newName)
        do {
            try FileManager.default.moveItem(at: url, to: newURL)
            SelectionManager.shared.updateLocalPath(from: url.path, to: newURL.path)
            isRenaming = false
            manager.loadContents()
            manager.selectedItem = newURL
            if let index = manager.allItems.firstIndex(where: { $0.url == newURL }) {
                manager.selectedIndex = index
            }
            dismiss()
        } catch {
            ToastManager.shared.show("Rename failed: \(error.localizedDescription)")
            isRenaming = false
            renameText = url.lastPathComponent
        }
    }

    private func calculateSize() {
        calculateFileSize(url: url, isDirectory: isDirectory) { sizeStr, count in
            fileSize = sizeStr
            itemCount = count
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .textStyle(.buttons)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .trailing)

            Text(value)
                .textStyle(.buttons)
                .textSelection(.enabled)

            Spacer()
        }
    }
}

struct EmptyFolderView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("This folder is empty")
                .textStyle(.default)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptySearchResultsView: View {
    let searchText: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No results for \"\(searchText)\"")
                .textStyle(.default)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct RenameTextField: NSViewRepresentable {
    @Binding var text: String
    var onCommit: () -> Void
    var onCancel: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.delegate = context.coordinator
        textField.font = NSFont.systemFont(ofSize: 13)
        textField.isBordered = false
        textField.drawsBackground = true
        textField.backgroundColor = NSColor.textBackgroundColor
        textField.focusRingType = .none
        textField.cell?.usesSingleLineMode = true
        textField.cell?.wraps = false
        textField.cell?.isScrollable = true
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }

        // Focus and select text on first appearance
        if !context.coordinator.didFocus {
            context.coordinator.didFocus = true
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
                // Select filename without extension
                if let ext = text.split(separator: ".").last, text.contains(".") && ext.count < text.count - 1 {
                    let nameLength = text.count - ext.count - 1
                    nsView.currentEditor()?.selectedRange = NSRange(location: 0, length: nameLength)
                } else {
                    nsView.selectText(nil)
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: RenameTextField
        var didFocus = false

        init(_ parent: RenameTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                parent.text = textField.stringValue
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onCommit()
                return true
            } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onCancel()
                return true
            }
            return false
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            // Check if ended by Return/Tab (already handled) vs actual blur
            if let movement = obj.userInfo?["NSTextMovement"] as? Int,
               movement == NSReturnTextMovement || movement == NSTabTextMovement {
                return
            }
            parent.onCancel()
        }
    }
}
