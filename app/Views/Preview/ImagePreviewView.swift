import SwiftUI
import AppKit

struct ImagePreviewView: View {
    let url: URL

    var body: some View {
        VStack(spacing: 0) {
            PreviewHeader(title: "Image preview", icon: "photo.fill", color: .purple)
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
                            .textStyle(.buttons)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 40)
                }
            }
        }
    }
}
