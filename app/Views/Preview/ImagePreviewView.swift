import SwiftUI

struct ImagePreviewView: View {
    let url: URL

    var body: some View {
        VStack(spacing: 0) {
            PreviewHeader(title: "Image preview", icon: "photo.fill", color: .purple)
            Divider()
            HTMLPreviewView(bodyHTML: Self.body(for: url), extraCSS: Self.css)
        }
    }

    private static let css = """
    body { padding: 0; display: flex; align-items: center; justify-content: center; min-height: 100vh; }
    img { max-width: 100%; max-height: 100vh; height: auto; object-fit: contain; }
    .err { color: #888; text-align: center; padding: 40px; }
    """

    private static func body(for url: URL) -> String {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return "<div class=\"err\">Unable to load image</div>"
        }
        let src = HTMLPreviewView.fileSrc(for: url)
        return """
        <img src="\(src)" onerror="this.remove(); document.getElementById('err').hidden = false">
        <div id="err" class="err" hidden>Unable to load image</div>
        """
    }
}
