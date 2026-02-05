import SwiftUI

struct MakefilePreviewView: View {
    let url: URL
    @ObservedObject private var settings = AppSettings.shared
    @State private var content: String = ""
    @State private var targets: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                PreviewHeader(title: url.lastPathComponent, icon: "hammer.fill", color: .orange)

                Spacer()

                // Font size controls
                HStack(spacing: 4) {
                    Button(action: { settings.decreaseFontSize() }) {
                        Image(systemName: "minus")
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.borderless)

                    Text("\(Int(settings.previewFontSize))px")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: 32)

                    Button(action: { settings.increaseFontSize() }) {
                        Image(systemName: "plus")
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.trailing, 8)
            }
            Divider()

            // Target buttons
            if !targets.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(targets, id: \.self) { target in
                            Button(action: { runTarget(target) }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 10))
                                    Text(target)
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                Divider()
            }

            // Syntax highlighted content
            SyntaxHighlightView(code: content, language: "makefile", fontSize: settings.previewFontSize)
        }
        .onAppear { loadContent() }
        .onChange(of: url) { _ in loadContent() }
    }

    private func loadContent() {
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            content = String(text.prefix(100000))
            parseTargets(from: text)
        } else {
            content = "Unable to load file"
            targets = []
        }
    }

    private func parseTargets(from text: String) {
        var foundTargets: [String] = []
        let lines = text.components(separatedBy: .newlines)

        for line in lines {
            // Match lines like "target:" or "target: dependency"
            // Skip lines starting with tab/space (recipe lines)
            // Skip .PHONY and other special targets
            if line.hasPrefix("\t") || line.hasPrefix(" ") || line.isEmpty {
                continue
            }

            if let colonIndex = line.firstIndex(of: ":") {
                // Check it's not ::= or := (variable assignment)
                let afterColon = line.index(after: colonIndex)
                if afterColon < line.endIndex {
                    let nextChar = line[afterColon]
                    if nextChar == "=" || nextChar == ":" {
                        continue
                    }
                }

                let target = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)

                // Skip special targets, variables, and empty
                if target.isEmpty ||
                   target.hasPrefix(".") ||
                   target.hasPrefix("$") ||
                   target.contains("=") ||
                   target.contains("%") ||
                   target.contains(" ") {
                    continue
                }

                foundTargets.append(target)
            }
        }

        targets = foundTargets
    }

    private func runTarget(_ target: String) {
        let directory = url.deletingLastPathComponent().path

        // Open Terminal and run make command
        let script = """
        tell application "Terminal"
            activate
            do script "cd '\(directory)' && make \(target)"
        end tell
        """

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }
}
