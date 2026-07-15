import SwiftUI
import AppKit

// Notification for when a file/folder is opened from outside (Finder, open -a, etc.)
extension Notification.Name {
    static let openPathRequest = Notification.Name("openPathRequest")
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        NotificationCenter.default.post(name: .openPathRequest, object: url)
    }
}

@main
struct FileExplorerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    static var initialPath: URL?
    static var initialFile: URL?

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
            Self.resolvePathArgument(path)
        }
    }

    static func resolvePathArgument(_ path: String) {
        // Remote source URLs (e.g. ssh://root@host/var/log) navigate directly
        if path.contains("://"), let url = URL(string: path), url.scheme == "ssh" || url.scheme == "sftp" {
            Self.initialPath = url
            Self.initialFile = nil
            return
        }

        var isDirectory: ObjCBool = false
        let resolvedPath: String

        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) {
            resolvedPath = path
        } else {
            let expanded = NSString(string: path).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory) {
                resolvedPath = expanded
            } else {
                return
            }
        }

        if isDirectory.boolValue {
            Self.initialPath = URL(fileURLWithPath: resolvedPath)
            Self.initialFile = nil
        } else {
            let fileURL = URL(fileURLWithPath: resolvedPath)
            Self.initialPath = fileURL.deletingLastPathComponent()
            Self.initialFile = fileURL
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About \(Self.appName)") {
                    Self.showAboutPanel()
                }
            }
        }

        Settings {
            SettingsView()
        }
    }

    private static let githubURL = "https://github.com/dux/file_explorer_swift"

    private static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "File Explorer"
    }

    private static func showAboutPanel() {
        let credits = NSMutableAttributedString(
            string: "github.com/dux/file_explorer_swift",
            attributes: [
                .link: URL(string: githubURL) as Any,
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            ]
        )
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        credits.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: credits.length))

        NSApplication.shared.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
