import SwiftUI

struct SelectionPane: View {
    @ObservedObject var manager: FileExplorerManager
    @ObservedObject var selection = SelectionManager.shared

    private var selectedItems: [FileItem] { selection.sortedItems }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.green)
                Text("Selection")
                    .textStyle(.default, weight: .semibold)
                Spacer()
                Button(action: { manager.currentPane = .browser }) {
                    Image(systemName: "xmark")
                        .textStyle(.small)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            if !selection.isEmpty {
                // Show selected items
                VStack(alignment: .leading, spacing: 16) {
                    Text("\(selection.count) item\(selection.count == 1 ? "" : "s") selected")
                        .textStyle(.default, weight: .medium)

                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(selectedItems, id: \.id) { item in
                                SelectionPaneItemRow(item: item, selection: selection)
                            }
                        }
                    }

                    // Actions for selection
                    Button(action: {
                        selection.clear()
                    }) {
                        Label("Clear all", systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                }
                .padding()

                Spacer()
            } else {
                // No selection
                VStack(spacing: 16) {
                    Image(systemName: "square.dashed")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No file selected")
                        .textStyle(.default)
                        .foregroundColor(.secondary)
                    Text("Press Space on a file to select it")
                        .textStyle(.small)
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct SelectionPaneItemRow: View {
    let item: FileItem
    @ObservedObject var selection: SelectionManager

    private var iconName: String {
        switch item.source {
        case .local:
            return item.isDirectory ? "folder.fill" : "doc.fill"
        case .iPhone:
            return "iphone"
        }
    }

    private var iconColor: Color {
        switch item.source {
        case .local:
            return item.isDirectory ? .blue : .secondary
        case .iPhone:
            return .pink
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .foregroundColor(iconColor)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .textStyle(.buttons)
                Text(item.displayPath)
                    .textStyle(.small)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(action: {
                selection.remove(item)
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(6)
    }
}
