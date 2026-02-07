import Foundation

struct MovieInfo: Codable, Sendable {
    let title: String
    let year: String
    let rated: String
    let runtime: String
    let genre: String
    let director: String
    let actors: String
    let plot: String
    let posterURL: String
    let imdbRating: String
    let imdbID: String
    let type: String

    var imdbURL: String {
        "https://www.imdb.com/title/\(imdbID)/"
    }

    var topActors: [String] {
        actors.components(separatedBy: ", ").prefix(3).map { String($0) }
    }
}

@MainActor
class MovieManager {
    static let shared = MovieManager()

    nonisolated static let videoExtensions: Set<String> = ["avi", "mp4", "mkv", "m4v", "mov", "wmv", "flv", "webm", "ogv", "3gp", "mpg", "mpeg", "vob", "ts"]

    private var omdbKey: String {
        AppSettings.shared.omdbAPIKey
    }
    private var inFlightTasks: [String: Task<MovieInfo?, Never>] = [:]

    private init() {}

    // Check if a folder contains at least one video file
    nonisolated static func hasVideoFile(in folderURL: URL) -> Bool {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return false }
        return contents.contains { videoExtensions.contains($0.pathExtension.lowercased()) }
    }

    // Find the first video file in a folder (for title extraction)
    nonisolated static func firstVideoFile(in folderURL: URL) -> URL? {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return nil }
        return contents.first { videoExtensions.contains($0.pathExtension.lowercased()) }
    }

    // Extract movie title and year from a name (folder or filename)
    // Examples: "The Matrix (1999)", "Inception.2010.1080p", "Cabeza.de.Vaca.1991.DVDRip.xxx.avi"
    nonisolated static func detectMovie(folderName: String) -> (title: String, year: String)? {
        // Strip file extension if present
        var name = folderName
        let ext = (name as NSString).pathExtension.lowercased()
        if videoExtensions.contains(ext) {
            name = (name as NSString).deletingPathExtension
        }

        // Pattern 1: "Title (YYYY)" - most common
        let parenPattern = /^(.+?)\s*\((\d{4})\)/
        if let match = try? parenPattern.firstMatch(in: name) {
            let year = String(match.2)
            if let y = Int(year), y >= 1900 && y <= 2100 {
                let title = cleanTitle(String(match.1))
                if !title.isEmpty { return (title, year) }
            }
        }

        // Pattern 2: "Title.YYYY." or "Title YYYY " with dots/spaces as separators
        let dotPattern = /^(.+?)[\.\s_-]+(\d{4})(?:[\.\s_-]|$)/
        if let match = try? dotPattern.firstMatch(in: name) {
            let year = String(match.2)
            if let y = Int(year), y >= 1900 && y <= 2100 {
                let title = cleanTitle(String(match.1))
                if !title.isEmpty { return (title, year) }
            }
        }

        // Pattern 3: just has a 4-digit year somewhere
        let yearPattern = /\b(\d{4})\b/
        let matches = name.matches(of: yearPattern)
        for match in matches {
            let year = String(match.1)
            if let y = Int(year), y >= 1900 && y <= 2100 {
                // Title is everything before the year
                if let range = name.range(of: year) {
                    let before = String(name[name.startIndex..<range.lowerBound])
                    let title = cleanTitle(before)
                    if !title.isEmpty { return (title, year) }
                }
            }
        }

        return nil
    }

    nonisolated private static func cleanTitle(_ raw: String) -> String {
        var title = raw
        // Replace dots, underscores with spaces
        title = title.replacingOccurrences(of: ".", with: " ")
        title = title.replacingOccurrences(of: "_", with: " ")
        title = title.replacingOccurrences(of: "-", with: " ")
        // Remove common release tags
        let removals = ["1080p", "720p", "2160p", "4k", "uhd", "hdr",
                        "bluray", "blu ray", "brrip", "bdrip", "dvdrip",
                        "webrip", "web dl", "hdtv", "x264", "x265", "h264", "h265",
                        "aac", "dts", "ac3", "remux", "repack", "proper",
                        "extended", "directors cut", "unrated", "theatrical"]
        let lower = title.lowercased()
        for tag in removals {
            if let range = lower.range(of: tag) {
                title = String(title[title.startIndex..<range.lowerBound])
            }
        }
        // Trim whitespace
        title = title.trimmingCharacters(in: .whitespaces)
        return title
    }

    // Cache file name: .fe-FILENAME.json for files, .fe-movie.json for folders
    nonisolated private static func cacheFileURL(for url: URL, isDir: Bool) -> URL {
        if isDir {
            return url.appendingPathComponent(".fe-movie.json")
        } else {
            let dir = url.deletingLastPathComponent()
            let name = url.lastPathComponent
            return dir.appendingPathComponent(".fe-\(name).json")
        }
    }

    // Check if URL is a movie (folder or file) and return cached or fetched info
    func getMovieInfo(for url: URL) async -> MovieInfo? {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)

        let detected: (title: String, year: String)

        if isDir.boolValue {
            if let fromFolder = Self.detectMovie(folderName: url.lastPathComponent) {
                detected = fromFolder
            } else if let videoFile = Self.firstVideoFile(in: url),
                      let fromFile = Self.detectMovie(folderName: videoFile.lastPathComponent) {
                detected = fromFile
            } else {
                return nil
            }
        } else {
            guard let fromFile = Self.detectMovie(folderName: url.lastPathComponent) else {
                return nil
            }
            detected = fromFile
        }

        let cacheFile = Self.cacheFileURL(for: url, isDir: isDir.boolValue)

        // Check cache first (off main thread)
        let cf = cacheFile
        let cached: MovieInfo? = await Task.detached(priority: .utility) {
            return Self.loadCache(from: cf)
        }.value
        if let cached { return cached }

        // Deduplicate in-flight requests
        let taskKey = url.path
        if let existing = inFlightTasks[taskKey] {
            return await existing.value
        }

        let title = detected.title
        let year = detected.year

        let task = Task.detached(priority: .utility) { () -> MovieInfo? in
            let searchTerm = year.isEmpty ? title : "\(title) \(year)"
            if let info = await Self.lookupMovie(searchTerm) {
                Self.saveCache(info, to: cf)
                return info
            }
            return nil
        }

        inFlightTasks[taskKey] = task
        let result = await task.value
        inFlightTasks.removeValue(forKey: taskKey)
        return result
    }

    nonisolated private static func loadCache(from url: URL) -> MovieInfo? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let info = try? JSONDecoder().decode(MovieInfo.self, from: data) {
            return info
        }
        // Corrupt — delete
        try? FileManager.default.removeItem(at: url)
        return nil
    }

    nonisolated private static func saveCache(_ info: MovieInfo, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(info) else { return }
        try? data.write(to: url, options: .atomic)
    }

    nonisolated private static func fetchFromOMDB(title: String, year: String, apiKey: String) async -> MovieInfo? {
        guard let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }

        let urlString = "https://www.omdbapi.com/?t=\(encodedTitle)&y=\(year)&plot=short&apikey=\(apiKey)"
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }

            // Check if OMDB returned an error
            if let responseStr = json["Response"] as? String, responseStr == "False" {
                // Try without year as fallback
                return await fetchFromOMDB(titleOnly: title, apiKey: apiKey)
            }

            return parseOMDBResponse(json)
        } catch {
            return nil
        }
    }

    nonisolated private static func fetchFromOMDB(imdbID: String, apiKey: String) async -> MovieInfo? {
        let urlString = "https://www.omdbapi.com/?i=\(imdbID)&plot=short&apikey=\(apiKey)"
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            if let responseStr = json["Response"] as? String, responseStr == "False" {
                return nil
            }
            return parseOMDBResponse(json)
        } catch {
            return nil
        }
    }

    // Extract IMDB ID from URL like https://www.imdb.com/title/tt0133093/
    nonisolated static func extractIMDBID(from input: String) -> String? {
        let pattern = /tt\d{7,}/
        if let match = try? pattern.firstMatch(in: input) {
            return String(match.0)
        }
        return nil
    }

    // Fetch movie info by IMDB ID and cache it for the given folder/file URL
    func getMovieInfoByIMDB(id imdbID: String, for url: URL) async -> MovieInfo? {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        let cacheFile = Self.cacheFileURL(for: url, isDir: isDir.boolValue)
        let cf = cacheFile

        let info = await Task.detached(priority: .utility) {
            await Self.scrapeIMDB(id: imdbID)
        }.value

        if let info {
            let cacheDest = cf
            Task.detached(priority: .utility) {
                Self.saveCache(info, to: cacheDest)
            }
        }
        return info
    }

    // Pure lookup: search term -> MovieInfo
    // Try OMDB API first (fast) if key is configured, then fall back to DuckDuckGo -> IMDB scraping
    nonisolated static func lookupMovie(_ searchTerm: String) async -> MovieInfo? {
        let detected = detectMovie(folderName: searchTerm)
        let title = detected?.title ?? searchTerm
        let year = detected?.year ?? ""

        // Try OMDB API first if key is available (much faster)
        let apiKey = await MainActor.run { AppSettings.shared.omdbAPIKey }
        if !apiKey.isEmpty {
            if let info = await fetchFromOMDB(title: title, year: year, apiKey: apiKey) {
                return info
            }
        }

        // Fall back to DuckDuckGo -> IMDB scraping
        guard let imdbID = await searchForIMDBID(title: title, year: year) else { return nil }
        return await scrapeIMDB(id: imdbID)
    }

    // Scrape IMDB page JSON-LD structured data
    nonisolated static func scrapeIMDB(id imdbID: String) async -> MovieInfo? {
        guard let url = URL(string: "https://www.imdb.com/title/\(imdbID)/") else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let html = String(data: data, encoding: .utf8) else { return nil }
            return parseIMDBPage(html: html, imdbID: imdbID)
        } catch {
            return nil
        }
    }

    nonisolated private static func parseIMDBPage(html: String, imdbID: String) -> MovieInfo? {
        // Extract JSON-LD block
        let ldPattern = /<script type="application\/ld\+json">(.*?)<\/script>/
        guard let match = try? ldPattern.firstMatch(in: html) else { return nil }
        let jsonStr = String(match.1)
        guard let jsonData = jsonStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let title = json["name"] as? String else {
            return nil
        }

        // Year from datePublished "2012-02-11"
        let year: String
        if let dateStr = json["datePublished"] as? String, dateStr.count >= 4 {
            year = String(dateStr.prefix(4))
        } else {
            year = "N/A"
        }

        // Runtime from ISO 8601 duration "PT2H15M"
        let runtime: String
        if let dur = json["duration"] as? String {
            runtime = parseISO8601Duration(dur)
        } else {
            runtime = "N/A"
        }

        // Genre
        let genre: String
        if let arr = json["genre"] as? [String] {
            genre = arr.joined(separator: ", ")
        } else if let str = json["genre"] as? String {
            genre = str
        } else {
            genre = "N/A"
        }

        // Director
        let director: String
        if let arr = json["director"] as? [[String: Any]] {
            director = arr.compactMap { $0["name"] as? String }.joined(separator: ", ")
        } else {
            director = "N/A"
        }

        // Actors
        let actors: String
        if let arr = json["actor"] as? [[String: Any]] {
            actors = arr.compactMap { $0["name"] as? String }.joined(separator: ", ")
        } else {
            actors = "N/A"
        }

        // Plot
        let plot = json["description"] as? String ?? "N/A"

        // Poster
        let posterURL = json["image"] as? String ?? "N/A"

        // Rating
        let imdbRating: String
        if let agg = json["aggregateRating"] as? [String: Any],
           let val = agg["ratingValue"] {
            imdbRating = "\(val)"
        } else {
            imdbRating = "N/A"
        }

        // Content rating
        let rated = json["contentRating"] as? String ?? "N/A"

        // Type
        let type = (json["@type"] as? String ?? "Movie").lowercased()

        return MovieInfo(
            title: title,
            year: year,
            rated: rated,
            runtime: runtime,
            genre: genre,
            director: director,
            actors: actors,
            plot: plot,
            posterURL: posterURL,
            imdbRating: imdbRating,
            imdbID: imdbID,
            type: type
        )
    }

    // Parse ISO 8601 duration like "PT2H15M" -> "2h 15min"
    nonisolated private static func parseISO8601Duration(_ dur: String) -> String {
        var result = ""
        let hPattern = /(\d+)H/
        let mPattern = /(\d+)M/
        if let hMatch = try? hPattern.firstMatch(in: dur) {
            result += "\(hMatch.1)h "
        }
        if let mMatch = try? mPattern.firstMatch(in: dur) {
            result += "\(mMatch.1) min"
        }
        let trimmed = result.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "N/A" : trimmed
    }

    // Search DuckDuckGo for "imdb TITLE YEAR" and extract the first tt\d+ IMDB ID from results
    nonisolated private static func searchForIMDBID(title: String, year: String) async -> String? {
        let query = "imdb \(title) \(year)".trimmingCharacters(in: .whitespaces)
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://html.duckduckgo.com/html/?q=\(encoded)") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let html = String(data: data, encoding: .utf8) else { return nil }
            let pattern = /tt\d{7,}/
            if let match = try? pattern.firstMatch(in: html) {
                return String(match.0)
            }
        } catch {
            // Ignore — fallback failed
        }
        return nil
    }

    nonisolated private static func fetchFromOMDB(titleOnly title: String, apiKey: String) async -> MovieInfo? {
        guard let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }

        let urlString = "https://www.omdbapi.com/?t=\(encodedTitle)&plot=short&apikey=\(apiKey)"
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            if let responseStr = json["Response"] as? String, responseStr == "False" {
                return nil
            }
            return parseOMDBResponse(json)
        } catch {
            return nil
        }
    }

    nonisolated private static func parseOMDBResponse(_ json: [String: Any]) -> MovieInfo? {
        guard let title = json["Title"] as? String,
              let imdbID = json["imdbID"] as? String else {
            return nil
        }

        return MovieInfo(
            title: title,
            year: json["Year"] as? String ?? "N/A",
            rated: json["Rated"] as? String ?? "N/A",
            runtime: json["Runtime"] as? String ?? "N/A",
            genre: json["Genre"] as? String ?? "N/A",
            director: json["Director"] as? String ?? "N/A",
            actors: json["Actors"] as? String ?? "N/A",
            plot: json["Plot"] as? String ?? "N/A",
            posterURL: json["Poster"] as? String ?? "N/A",
            imdbRating: json["imdbRating"] as? String ?? "N/A",
            imdbID: imdbID,
            type: json["Type"] as? String ?? "movie"
        )
    }
}
