import SwiftUI

struct JSONPreviewView: View {
    let url: URL
    @ObservedObject private var settings = AppSettings.shared
    @State private var content: String = ""
    @State private var isFormatted: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            // Header with format button
            HStack(spacing: 8) {
                Image(systemName: "curlybraces")
                    .font(.system(size: 14))
                    .foregroundColor(.orange)

                Text(url.lastPathComponent)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                Spacer()

                Button(action: toggleFormat) {
                    HStack(spacing: 4) {
                        Image(systemName: isFormatted ? "text.alignleft" : "text.justify")
                            .font(.system(size: 12))
                        Text(isFormatted ? "Raw" : "Format")
                            .font(.system(size: 12))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)

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
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            SyntaxHighlightView(code: content, language: "json", fontSize: settings.previewFontSize)
        }
        .onAppear { loadContent() }
        .onChange(of: url) { _ in
            isFormatted = true
            loadContent()
        }
    }

    private func loadContent() {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            content = "Unable to load file"
            return
        }

        if isFormatted {
            content = formatJSON(text)
        } else {
            content = String(text.prefix(100000))
        }
    }

    private func toggleFormat() {
        isFormatted.toggle()
        loadContent()
    }

    private func formatJSON(_ text: String) -> String {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let formatted = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
              let result = String(data: formatted, encoding: .utf8) else {
            return text // Return original if can't parse
        }
        return result
    }
}
