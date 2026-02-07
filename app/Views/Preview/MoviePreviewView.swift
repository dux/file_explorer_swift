import SwiftUI
import AppKit

struct MoviePreviewView: View {
    let folderURL: URL
    @ObservedObject private var settings = AppSettings.shared
    @State private var movieInfo: MovieInfo?
    @State private var posterImage: NSImage?
    @State private var isLoading = true
    @State private var loadFailed = false

    private var hasAPIKey: Bool {
        !settings.omdbAPIKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            PreviewHeader(title: "Movie", icon: "film.fill", color: .orange)
            Divider()

            if !hasAPIKey {
                missingKeyView
            } else if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Looking up movie...")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let info = movieInfo {
                movieContent(info)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "film")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("Movie not found")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: folderURL) {
            guard hasAPIKey else { return }
            isLoading = true
            loadFailed = false
            posterImage = nil

            let info = await MovieManager.shared.getMovieInfo(for: folderURL)
            movieInfo = info
            isLoading = false

            if let info = info, info.posterURL != "N/A" {
                let hiRes = info.posterURL.replacingOccurrences(of: "SX300", with: "SX800")
                if let url = URL(string: hiRes) {
                    await loadPoster(from: url)
                }
            }
        }
    }

    private var missingKeyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "key.fill")
                .font(.system(size: 28))
                .foregroundColor(.secondary)

            Text("OMDB API key required")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)

            Text("Set your free API key in Settings to enable movie previews.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            HStack(spacing: 12) {
                Button("Open Settings") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Get free key") {
                    if let url = URL(string: "https://www.omdbapi.com/apikey.aspx") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func movieContent(_ info: MovieInfo) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    // Title + year
                    VStack(alignment: .leading, spacing: 4) {
                        Text(info.title)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.primary)
                            .lineLimit(2)

                        HStack(spacing: 8) {
                            Text(info.year)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.secondary)

                            if info.rated != "N/A" {
                                Text(info.rated)
                                    .font(.system(size: 12, weight: .semibold))
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
                                    .font(.system(size: 15))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    // Ratings row — clickable
                    HStack(spacing: 14) {
                        // IMDB
                        if info.imdbRating != "N/A" {
                            ratingBadge(label: "IMDb", value: info.imdbRating, badgeColor: .yellow, textColor: .black, url: info.imdbURL)
                        }

                        // Rotten Tomatoes
                        if info.rottenTomatoesRating != "N/A" {
                            ratingBadge(label: "RT", value: info.rottenTomatoesRating, badgeColor: .red, textColor: .white, url: info.rottenTomatoesURL)
                        }

                        // Metacritic
                        if info.metacriticRating != "N/A" {
                            ratingBadge(label: "MC", value: info.metacriticRating, badgeColor: .green, textColor: .white, url: "https://www.metacritic.com/search/\(info.title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? info.title)/")
                        }
                    }

                    // Genre
                    if info.genre != "N/A" {
                        Text(info.genre)
                            .font(.system(size: 15))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    // Plot
                    if info.plot != "N/A" {
                        Text(info.plot)
                            .font(.system(size: 15))
                            .foregroundColor(.primary.opacity(0.8))
                            .lineLimit(5)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // Director
                    if info.director != "N/A" {
                        HStack(alignment: .top, spacing: 6) {
                            Text("Director")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.secondary)
                                .frame(width: 65, alignment: .leading)
                            Text(info.director)
                                .font(.system(size: 15))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                        }
                    }

                    // Actors (top 3)
                    if info.actors != "N/A" {
                        HStack(alignment: .top, spacing: 6) {
                            Text("Cast")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.secondary)
                                .frame(width: 65, alignment: .leading)
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(info.topActors, id: \.self) { actor in
                                    Text(actor)
                                        .font(.system(size: 15))
                                        .foregroundColor(.primary)
                                }
                            }
                        }
                    }

                }
                .padding(14)

                // Poster below info
                if let poster = posterImage {
                    Divider()
                    Image(nsImage: poster)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipped()
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
                    .font(.system(size: 11, weight: .bold))
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

    private func loadPoster(from url: URL) async {
        let data: Data? = await Task.detached(priority: .utility) {
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
            return data
        }.value
        if let data, let image = NSImage(data: data) {
            posterImage = image
        }
    }
}
