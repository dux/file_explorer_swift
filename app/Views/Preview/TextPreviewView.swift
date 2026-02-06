import SwiftUI

struct TextPreviewView: View {
    let url: URL
    @ObservedObject private var settings = AppSettings.shared
    @State private var content: String = ""

    private var language: String {
        let ext = url.pathExtension.lowercased()
        if !ext.isEmpty {
            return SyntaxHighlightView.languageForExtension(ext)
        }
        return SyntaxHighlightView.languageForFilename(url.lastPathComponent)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                PreviewHeader(title: "Text preview", icon: "doc.text.fill", color: .blue)

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

            SyntaxHighlightView(code: content, language: language, fontSize: settings.previewFontSize)
        }
        .onAppear { loadContent() }
        .onChange(of: url) { _ in loadContent() }
    }

    private func loadContent() {
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            content = String(text.prefix(100000)) // Limit to 100k chars
        } else {
            content = "Unable to load file"
        }
    }
}
