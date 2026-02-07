import SwiftUI
import AppKit

struct MoviePreviewView: View {
    let folderURL: URL
    @State private var movieInfo: MovieInfo?
    @State private var posterImage: NSImage?
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
                        .font(.system(size: 11))
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
            posterImage = nil
            movieInfo = nil

            let info = await MovieManager.shared.getMovieInfo(for: folderURL)
            movieInfo = info
            isLoading = false

            if let info, info.posterURL != "N/A" {
                await loadPoster(from: info.posterURL)
            }
        }
    }

    private var notFoundView: some View {
        VStack(spacing: 12) {
            Image(systemName: "film")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text("Movie not found")
                .font(.system(size: 13))
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
                    .font(.system(size: 11))
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
        Task {
            let info = await MovieManager.shared.getMovieInfoByIMDB(id: imdbID, for: folderURL)
            movieInfo = info
            isLookingUp = false
            imdbInput = ""
            if let info, info.posterURL != "N/A" {
                await loadPoster(from: info.posterURL)
            }
        }
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

                    // IMDB rating + search links
                    HStack(spacing: 14) {
                        if info.imdbRating != "N/A" {
                            ratingBadge(label: "IMDb", value: info.imdbRating, badgeColor: .yellow, textColor: .black, url: info.imdbURL)
                        }

                        searchButton(label: "RT", color: .red, query: "site:rottentomatoes.com/m \(info.title) \(info.year)")
                        searchButton(label: "MC", color: .green, query: "site:metacritic.com \(info.title) \(info.year)")
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

    private func searchButton(label: String, color: Color, query: String) -> some View {
        Button(action: {
            let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            if let url = URL(string: "https://duckduckgo.com/?q=\(encoded)") {
                NSWorkspace.shared.open(url)
            }
        }) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
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

    private func loadPoster(from urlString: String) async {
        guard let url = URL(string: urlString) else { return }
        let data: Data? = await Task.detached(priority: .utility) {
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
            return data
        }.value
        if let data, let image = NSImage(data: data) {
            posterImage = image
        }
    }
}
