import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        TabView {
            GeneralSettingsView(settings: settings)
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            APISettingsView(settings: settings)
                .tabItem {
                    Label("API Keys", systemImage: "key")
                }
        }
        .frame(width: 450, height: 280)
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Preview font size")
                    Spacer()
                    HStack(spacing: 8) {
                        Button("-") { settings.decreaseFontSize() }
                            .frame(width: 24)
                        Text("\(Int(settings.previewFontSize))px")
                            .font(.system(size: 13, design: .monospaced))
                            .frame(width: 40)
                        Button("+") { settings.increaseFontSize() }
                            .frame(width: 24)
                    }
                }

                Toggle("Show preview pane", isOn: $settings.showPreviewPane)
            }

            Section {
                HStack {
                    Text("Config location")
                    Spacer()
                    Text("~/.config/dux-file-explorer/")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Button("Open config folder") {
                    NSWorkspace.shared.open(AppSettings.configBase)
                }
            }
        }
        .formStyle(.grouped)
        .padding(10)
    }
}

struct APISettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var omdbKey: String = ""

    var body: some View {
        Form {
            Section("Movie Preview (OMDB)") {
                HStack {
                    Text("OMDB API key")
                    Spacer()
                    TextField("API key", text: $omdbKey)
                        .frame(width: 180)
                        .textFieldStyle(.roundedBorder)
                }

                Button("Save key") {
                    settings.omdbAPIKey = omdbKey
                }
                .disabled(omdbKey.isEmpty)

                HStack(spacing: 4) {
                    Text("Get a free key at")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Button("omdbapi.com/apikey.aspx") {
                        if let url = URL(string: "https://www.omdbapi.com/apikey.aspx") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundColor(.blue)
                    .onHover { hovering in
                        if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(10)
        .onAppear {
            omdbKey = settings.omdbAPIKey
        }
    }
}
