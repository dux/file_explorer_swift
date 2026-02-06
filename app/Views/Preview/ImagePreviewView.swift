import SwiftUI
import AppKit

struct ImagePreviewView: View {
    let url: URL

    var body: some View {
        VStack(spacing: 0) {
            PreviewHeader(title: url.lastPathComponent, icon: "photo.fill", color: .purple)
            Divider()

            ScrollView {
                if let nsImage = NSImage(contentsOf: url) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        Text("Unable to load image")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 40)
                }
            }
        }
    }
}
