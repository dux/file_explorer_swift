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

                FontSizeControls(settings: settings)
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
