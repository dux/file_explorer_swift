import SwiftUI
import AppKit

@main
struct FileExplorerApp: App {
    static var initialPath: URL?

    init() {
        // Set dock/cmd-tab icon from bundle
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }

        // Check command line arguments for initial folder
        let args = CommandLine.arguments
        if args.count > 1 {
            let path = args[1]
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    FileExplorerApp.initialPath = URL(fileURLWithPath: path)
                } else {
                    // If it's a file, open its parent directory
                    FileExplorerApp.initialPath = URL(fileURLWithPath: path).deletingLastPathComponent()
                }
            } else {
                // Try expanding ~ for home directory
                let expanded = NSString(string: path).expandingTildeInPath
                if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory) {
                    if isDirectory.boolValue {
                        FileExplorerApp.initialPath = URL(fileURLWithPath: expanded)
                    } else {
                        FileExplorerApp.initialPath = URL(fileURLWithPath: expanded).deletingLastPathComponent()
                    }
                }
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
        }
    }
}
