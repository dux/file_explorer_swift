import SwiftUI
import AppKit

struct UninstallConfirmSheet: View {
    let appURL: URL
    let dataPaths: [URL]
    @Binding var isPresented: Bool
    let onComplete: () -> Void

    @State private var selectedPaths: Set<URL> = []
    @State private var isUninstalling = false

    private var appName: String {
        appURL.deletingPathExtension().lastPathComponent
    }

    private var home: String {
        FileManager.default.homeDirectoryForCurrentUser.path
    }

    private func displayPath(_ url: URL) -> String {
        let path = url.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                    .resizable()
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Uninstall \(appName)")
                        .font(.system(size: 16, weight: .semibold))
                    Text(appURL.path)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                SheetCloseButton(isPresented: $isPresented)
            }
            .padding(16)

            Divider()

            if dataPaths.isEmpty {
                VStack(spacing: 8) {
                    Text("No app data found")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Text("The app will be moved to Trash.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("App data found (\(dataPaths.count))")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button(selectedPaths.count == dataPaths.count ? "Deselect all" : "Select all") {
                            if selectedPaths.count == dataPaths.count {
                                selectedPaths.removeAll()
                            } else {
                                selectedPaths = Set(dataPaths)
                            }
                        }
                        .font(.system(size: 12))
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 4)

                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(dataPaths, id: \.path) { path in
                                let isSelected = selectedPaths.contains(path)
                                HStack(spacing: 8) {
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(isSelected ? .accentColor : .secondary)
                                        .font(.system(size: 14))

                                    Image(systemName: path.hasDirectoryPath ? "folder.fill" : "doc.fill")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 12))
                                        .frame(width: 16)

                                    Text(displayPath(path))
                                        .font(.system(size: 12, design: .monospaced))
                                        .lineLimit(1)
                                        .truncationMode(.middle)

                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 5)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if isSelected {
                                        selectedPaths.remove(path)
                                    } else {
                                        selectedPaths.insert(path)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
            }

            Divider()

            // Actions
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button(action: performUninstall) {
                    if isUninstalling {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 16, height: 16)
                    } else {
                        Text(selectedPaths.isEmpty ? "Move to Trash" : "Move to Trash with data")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isUninstalling)
            }
            .padding(16)
        }
        .frame(width: 480)
        .onAppear {
            selectedPaths = Set(dataPaths)
        }
    }

    private func performUninstall() {
        isUninstalling = true
        let fm = FileManager.default
        var trashed = 0
        var failed = 0

        do {
            try fm.trashItem(at: appURL, resultingItemURL: nil)
            trashed += 1
        } catch {
            failed += 1
        }

        for path in selectedPaths {
            do {
                try fm.trashItem(at: path, resultingItemURL: nil)
                trashed += 1
            } catch {
                failed += 1
            }
        }

        isUninstalling = false
        isPresented = false

        if failed > 0 {
            ToastManager.shared.showError("Uninstalled \(appName), but \(failed) item(s) failed to remove")
        } else if selectedPaths.isEmpty {
            ToastManager.shared.show("Moved \(appName) to Trash")
        } else {
            ToastManager.shared.show("Uninstalled \(appName) and removed \(selectedPaths.count) data item(s)")
        }

        onComplete()
    }
}
