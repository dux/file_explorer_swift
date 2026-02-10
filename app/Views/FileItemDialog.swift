import SwiftUI
import AppKit

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

            VStack(spacing: 2) {
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
