import SwiftUI
import AppKit

struct AppSelectorSheet: View {
    let targetURL: URL
    let fileType: String
    @ObservedObject var settings: AppSettings
    @Binding var isPresented: Bool

    @State private var searchText = ""
    @State private var allApps: [(url: URL, name: String, icon: NSImage)] = []
    @State private var isLoading = true

    private var filteredApps: [(url: URL, name: String, icon: NSImage)] {
        if searchText.isEmpty {
            return allApps
        }
        let query = searchText.lowercased()
        return allApps.filter { $0.name.lowercased().contains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Open with...")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(12)

            Divider()

            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Filter apps...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color(NSColor.textBackgroundColor))

            Divider()

            // App list
            if isLoading {
                Spacer()
                ProgressView()
                    .scaleEffect(0.8)
                Text("Loading apps...")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
                Spacer()
            } else if filteredApps.isEmpty {
                Spacer()
                Text("No apps found")
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filteredApps, id: \.url.path) { app in
                            AppRow(app: app) {
                                openWithApp(app)
                            }
                        }
                    }
                    .padding(8)
                }
            }
        }
        .frame(width: 350, height: 450)
        .background(Color(NSColor.controlBackgroundColor))
        .onAppear {
            loadAllApps()
        }
    }

    private func openWithApp(_ app: (url: URL, name: String, icon: NSImage)) {
        settings.addPreferredApp(for: fileType, appPath: app.url.path)
        NSWorkspace.shared.open([targetURL], withApplicationAt: app.url, configuration: NSWorkspace.OpenConfiguration())
        isPresented = false
    }

    private func loadAllApps() {
        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async {
            var apps: [(url: URL, name: String, icon: NSImage)] = []
            var seen = Set<String>()

            let appDirs = [
                URL(fileURLWithPath: "/Applications"),
                FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
            ]

            for dir in appDirs {
                if let contents = try? FileManager.default.contentsOfDirectory(
                    at: dir,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                ) {
                    for url in contents {
                        if url.pathExtension == "app" {
                            let name = url.deletingPathExtension().lastPathComponent
                            if !seen.contains(name) {
                                seen.insert(name)
                                let icon = NSWorkspace.shared.icon(forFile: url.path)
                                apps.append((url: url, name: name, icon: icon))
                            }
                        }
                    }
                }
            }

            // Sort alphabetically
            apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            DispatchQueue.main.async {
                self.allApps = apps
                self.isLoading = false
            }
        }
    }
}

struct AppRow: View {
    let app: (url: URL, name: String, icon: NSImage)
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: 24, height: 24)

                Text(app.name)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.accentColor.opacity(0.15) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
