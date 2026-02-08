import SwiftUI
import AppKit
import WebKit

struct MoviePreviewView: View {
    let folderURL: URL
    @State private var movieInfo: MovieInfo?
    @State private var isLoading = true
    @State private var imdbInput: String = ""
    @State private var isLookingUp = false

    var body: some View {
        VStack(spacing: 0) {
            PreviewHeader(title: "Movie", icon: "film.fill", color: .orange)
            Divider()

            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Looking up movie...")
                        .textStyle(.small)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let info = movieInfo {
                movieContent(info)
            } else {
                notFoundView
            }
        }
        .task(id: folderURL) {
            isLoading = true
            movieInfo = nil

            let info = await MovieManager.shared.getMovieInfo(for: folderURL)
            movieInfo = info
            isLoading = false
        }
    }

    private var notFoundView: some View {
        VStack(spacing: 12) {
            Image(systemName: "film")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text("Movie not found")
                .textStyle(.buttons)
                .foregroundColor(.secondary)

            Button("Search IMDB") {
                let name = folderURL.lastPathComponent
                let detected = MovieManager.detectMovie(folderName: name)
                let query = detected.map { "\($0.title) \($0.year)" } ?? name
                let encoded = "imdb \(query)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
                if let url = URL(string: "https://www.google.com/search?q=\(encoded)") {
                    NSWorkspace.shared.open(url)
                }
            }
            .controlSize(.small)

            VStack(spacing: 8) {
                Text("Paste IMDB URL")
                    .textStyle(.small)
                    .foregroundColor(.secondary)
                HStack(spacing: 6) {
                    TextField("https://imdb.com/title/tt...", text: $imdbInput)
                        .styledInput()
                        .onSubmit { lookupIMDB() }
                    Button(action: lookupIMDB) {
                        if isLookingUp {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "arrow.right.circle.fill")
                        }
                    }
                    .disabled(imdbInput.isEmpty || isLookingUp)
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func lookupIMDB() {
        guard let imdbID = MovieManager.extractIMDBID(from: imdbInput) else { return }
        isLookingUp = true
        Task { @MainActor in
            let info = await MovieManager.shared.getMovieInfoByIMDB(id: imdbID, for: folderURL)
            movieInfo = info
            isLookingUp = false
            imdbInput = ""
        }
    }

    @ViewBuilder
    private func movieContent(_ info: MovieInfo) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(info.title)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.primary)
                            .lineLimit(2)

                        HStack(spacing: 8) {
                            Text(info.year)
                                .textStyle(.default, weight: .medium)
                                .foregroundColor(.secondary)

                            if info.rated != "N/A" {
                                Text(info.rated)
                                    .textStyle(.small, weight: .semibold)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 3)
                                            .stroke(Color.secondary.opacity(0.5), lineWidth: 0.5)
                                    )
                            }

                            if info.runtime != "N/A" {
                                Text(info.runtime)
                                    .textStyle(.default)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    HStack(spacing: 14) {
                        if info.imdbRating != "N/A" {
                            ratingBadge(label: "IMDb", value: info.imdbRating, badgeColor: .yellow, textColor: .black, url: info.imdbURL)
                        }

                        searchButton(label: "RT", color: .red, query: "site:rottentomatoes.com/m \(info.title) \(info.year)")
                        searchButton(label: "MC", color: .green, query: "site:metacritic.com \(info.title) \(info.year)")
                    }

                    if info.genre != "N/A" {
                        Text(info.genre)
                            .textStyle(.default)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    if info.plot != "N/A" {
                        Text(info.plot)
                            .textStyle(.default)
                            .foregroundColor(.primary.opacity(0.8))
                            .lineLimit(5)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if info.director != "N/A" {
                        HStack(alignment: .top, spacing: 6) {
                            Text("Director")
                                .textStyle(.default, weight: .semibold)
                                .foregroundColor(.secondary)
                                .frame(width: 65, alignment: .leading)
                            Text(info.director)
                                .textStyle(.default)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                        }
                    }

                    if info.actors != "N/A" {
                        HStack(alignment: .top, spacing: 6) {
                            Text("Cast")
                                .textStyle(.default, weight: .semibold)
                                .foregroundColor(.secondary)
                                .frame(width: 65, alignment: .leading)
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(info.topActors, id: \.self) { actor in
                                    Text(actor)
                                        .textStyle(.default)
                                        .foregroundColor(.primary)
                                }
                            }
                        }
                    }
                }
                .padding(14)

                if info.posterURL != "N/A" {
                    Divider()
                    if let posterURL = URL(string: info.posterURL) {
                        PosterHTMLImageView(imageURL: posterURL)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 620, maxHeight: .infinity, alignment: .top)
                    } else {
                        Text("Poster unavailable")
                            .textStyle(.small)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                    }
                }
            }
        }
    }

    private func ratingBadge(label: String, value: String, badgeColor: Color, textColor: Color, url: String) -> some View {
        Button(action: {
            if let link = URL(string: url) {
                NSWorkspace.shared.open(link)
            }
        }) {
            HStack(spacing: 5) {
                Text(label)
                    .textStyle(.small, weight: .bold)
                    .foregroundColor(textColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(badgeColor)
                    .cornerRadius(3)

                Text(value)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    private func searchButton(label: String, color: Color, query: String) -> some View {
        Button(action: {
            let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            if let url = URL(string: "https://duckduckgo.com/?q=\(encoded)") {
                NSWorkspace.shared.open(url)
            }
        }) {
            Text(label)
                .textStyle(.small, weight: .bold)
                .foregroundColor(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(color)
                .cornerRadius(3)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

private struct PosterHTMLImageView: NSViewRepresentable {
    let imageURL: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.load(url: imageURL, in: webView)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.load(url: imageURL, in: nsView)
    }

    final class Coordinator {
        private var lastURL: URL?

        @MainActor
        func load(url: URL, in webView: WKWebView) {
            guard lastURL != url else { return }
            lastURL = url
            webView.loadHTMLString(Self.html(for: url), baseURL: nil)
        }

        private static func html(for url: URL) -> String {
            let jsURL = escapeForSingleQuotedJS(upgradePosterURL(url).absoluteString)
            return """
            <!doctype html>
            <html>
            <head>
              <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
              <style>
                html, body {
                  margin: 0;
                  padding: 0;
                  width: 100%;
                  height: 100%;
                  overflow: hidden;
                  background: transparent;
                  font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                }
                #wrap {
                  width: 100%;
                  height: 100%;
                  display: flex;
                  align-items: center;
                  justify-content: center;
                  position: relative;
                }
                #spinner {
                  width: 20px;
                  height: 20px;
                  border: 2px solid rgba(128,128,128,0.25);
                  border-top-color: rgba(128,128,128,0.95);
                  border-radius: 50%;
                  animation: spin 0.8s linear infinite;
                }
                #img {
                  width: 100%;
                  height: 100%;
                  object-fit: contain;
                  object-position: top center;
                  display: none;
                }
                #error {
                  display: none;
                  color: #8a8a8a;
                  font-size: 12px;
                }
                @keyframes spin {
                  to { transform: rotate(360deg); }
                }
              </style>
            </head>
            <body>
              <div id=\"wrap\">
                <div id=\"spinner\"></div>
                <img id=\"img\" alt=\"Poster\" />
                <div id=\"error\">Poster unavailable</div>
              </div>
              <script>
                const img = document.getElementById('img');
                const spinner = document.getElementById('spinner');
                const error = document.getElementById('error');

                img.onload = function () {
                  spinner.style.display = 'none';
                  error.style.display = 'none';
                  img.style.display = 'block';
                };

                img.onerror = function () {
                  spinner.style.display = 'none';
                  img.style.display = 'none';
                  error.style.display = 'block';
                };

                img.src = '\(jsURL)';
              </script>
            </body>
            </html>
            """
        }

        private static func escapeForSingleQuotedJS(_ input: String) -> String {
            var out = input.replacingOccurrences(of: "\\", with: "\\\\")
            out = out.replacingOccurrences(of: "'", with: "\\'")
            out = out.replacingOccurrences(of: "\n", with: "")
            out = out.replacingOccurrences(of: "\r", with: "")
            return out
        }

        // IMDb posters often include a size token like ._V1_...jpg; request a larger height to preserve poster framing.
        private static func upgradePosterURL(_ url: URL) -> URL {
            let absolute = url.absoluteString
            guard absolute.contains("media-amazon.com"),
                  let range = absolute.range(of: "._V1_") else {
                return url
            }

            let prefix = absolute[..<range.lowerBound]
            let upgraded = "\(prefix)._V1_SY2000_.jpg"
            return URL(string: upgraded) ?? url
        }
    }
}
