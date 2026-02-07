import SwiftUI
import AppKit

struct iPhoneActionsPane: View {
    @ObservedObject var manager: FileExplorerManager
    @ObservedObject var deviceManager = iPhoneManager.shared
    @ObservedObject var selection = SelectionManager.shared

    private var selectedFile: iPhoneFile? {
        deviceManager.selectedFile
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 2) {
                Text("iPhone Actions")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)

                if let file = selectedFile {
                    Text(file.name)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("No file selected")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            // File actions
            VStack(spacing: 2) {
                ActionButton(
                    icon: "checkmark.circle",
                    title: "Add to selection",
                    color: .green
                ) {
                    addSelectedToSelection()
                }
                .disabled(selectedFile == nil || selectedFile?.isDirectory == true)

                ActionButton(
                    icon: "arrow.down.circle",
                    title: "Download to Mac",
                    color: .blue
                ) {
                    Task {
                        await downloadSelectedFile()
                    }
                }
                .disabled(selectedFile == nil || selectedFile?.isDirectory == true)

                ActionButton(
                    icon: "trash",
                    title: "Delete from iPhone",
                    color: .red
                ) {
                    Task {
                        await deleteSelectedFile()
                    }
                }
                .disabled(selectedFile == nil)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)

            Divider()

            // Selection info & actions
            VStack(alignment: .leading, spacing: 2) {
                Text("Selection (\(selection.count))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)

                let _ = selection.version
                let iPhoneCount = selection.iPhoneItems.count
                let localCount = selection.localItems.count

                if iPhoneCount > 0 {
                    HStack(spacing: 10) {
                        Image(systemName: "iphone")
                            .font(.system(size: 14))
                            .foregroundColor(.pink)
                            .frame(width: 20)
                        Text("\(iPhoneCount) iPhone file(s)")
                            .font(.system(size: 13))
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)

                    ActionButton(
                        icon: "arrow.down.doc",
                        title: "Download here",
                        color: .blue
                    ) {
                        Task {
                            await downloadIPhoneSelection()
                        }
                    }
                }

                if localCount > 0 {
                    HStack(spacing: 10) {
                        Image(systemName: "desktopcomputer")
                            .font(.system(size: 14))
                            .foregroundColor(.blue)
                            .frame(width: 20)
                        Text("\(localCount) Mac file(s)")
                            .font(.system(size: 13))
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .padding(.top, iPhoneCount > 0 ? 4 : 0)

                    ActionButton(
                        icon: "arrow.up.doc",
                        title: "Upload to iPhone",
                        color: .green
                    ) {
                        Task {
                            await uploadMacSelection()
                        }
                    }
                }

                if !selection.isEmpty {
                    ActionButton(
                        icon: "xmark.circle",
                        title: "Clear selection",
                        color: .orange
                    ) {
                        selection.clear()
                    }
                }

                if selection.isEmpty {
                    Text("No files selected")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 8)

            Spacer()
        }
    }

    private func addSelectedToSelection() {
        guard let file = selectedFile,
              let device = deviceManager.currentDevice,
              case .appDocuments(let appId, let appName) = deviceManager.browseMode else { return }

        selection.addIPhone(file, deviceId: device.id, appId: appId, appName: appName)
    }

    private func downloadSelectedFile() async {
        guard let file = selectedFile, !file.isDirectory else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Download Here"
        panel.message = "Choose destination folder for \(file.name)"

        guard let keyWindow = NSApp.keyWindow else { return }
        let response = await panel.beginSheetModal(for: keyWindow)
        guard response == .OK, let url = panel.url else { return }

        let destinationPath = url.appendingPathComponent(file.name)
        if let downloadedURL = await deviceManager.downloadFile(file) {
            do {
                try FileManager.default.copyItem(at: downloadedURL, to: destinationPath)
                ToastManager.shared.show("Downloaded \(file.name)")
            } catch {
                ToastManager.shared.show("Failed to save file")
            }
        }
    }

    private func deleteSelectedFile() async {
        guard let file = selectedFile else { return }

        let success = await deviceManager.deleteFile(file)
        if success {
            ToastManager.shared.show("Deleted \(file.name)")
            await deviceManager.loadFiles()
        } else {
            ToastManager.shared.show("Failed to delete \(file.name)")
        }
    }

    private func downloadIPhoneSelection() async {
        // Download to current iPhone folder's parent path
        let count = await selection.downloadIPhoneItems(to: manager.currentPath, move: false)
        ToastManager.shared.show("Downloaded \(count) file(s)")
        manager.refresh()
    }

    private func uploadMacSelection() async {
        guard let device = deviceManager.currentDevice,
              case .appDocuments(let appId, _) = deviceManager.browseMode else { return }

        let count = await selection.uploadLocalItems(
            deviceId: device.id,
            appId: appId,
            toPath: deviceManager.currentPath
        )
        ToastManager.shared.show("Uploaded \(count) file(s)")
        await deviceManager.loadFiles()
    }
}
