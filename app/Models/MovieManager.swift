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

    nonisolated static let videoExtensions: Set<String> = [
        "avi", "mp4", "mkv", "m4v", "mov", "wmv", "flv",
        "webm", "ogv", "3gp", "mpg", "mpeg", "vob", "ts"
    ]

    private var omdbKey: String { AppSettings.shared.omdbAPIKey }
    private var inFlightTasks: [String: Task<MovieInfo?, Never>] = [:]

    nonisolated private static let networkSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 20
        return URLSession(configuration: config)
    }()

    private init() {}

    // MARK: - Public API

    func getMovieInfo(for url: URL) async -> MovieInfo? {
        let prep = await Task.detached(priority: .userInitiated) {
            Self.prepareMovieInfo(for: url)
        }.value

        guard let prep else { return nil }
        if let cached = prep.cached { return cached }

        let taskKey = url.path
        if let existing = inFlightTasks[taskKey] {
            return await existing.value
        }

        let title = prep.detected.title
        let year = prep.detected.year
        let apiKey = omdbKey
        let cacheFile = prep.cacheFile

        let task = Task.detached(priority: .utility) { () -> MovieInfo? in
            let searchTerm = year.isEmpty ? title : "\(title) \(year)"
            guard let info = await Self.lookupMovie(searchTerm, apiKey: apiKey) else { return nil }
            Self.saveCache(info, to: cacheFile)
            return info
        }

        inFlightTasks[taskKey] = task
        let result = await task.value
        inFlightTasks.removeValue(forKey: taskKey)
        return result
    }

    func getMovieInfoByIMDB(id imdbID: String, for url: URL) async -> MovieInfo? {
        await Task.detached(priority: .utility) { () -> MovieInfo? in
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            let cacheFile = Self.cacheFileURL(for: url, isDir: isDir.boolValue)
            guard let info = await Self.scrapeIMDB(id: imdbID) else { return nil }
            Self.saveCache(info, to: cacheFile)
            return info
        }.value
    }

    // MARK: - Detection

    nonisolated static func hasVideoFile(in folderURL: URL) -> Bool {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: folderURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return false }
        return contents.contains { videoExtensions.contains($0.pathExtension.lowercased()) }
    }

    nonisolated static func firstVideoFile(in folderURL: URL) -> URL? {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: folderURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return nil }
        return contents.first { videoExtensions.contains($0.pathExtension.lowercased()) }
    }

    nonisolated static func detectMovie(folderName: String) -> (title: String, year: String)? {
        var name = folderName
        let ext = (name as NSString).pathExtension.lowercased()
        if videoExtensions.contains(ext) {
            name = (name as NSString).deletingPathExtension
        }

        // "Title (YYYY)"
        let parenPattern = /^(.+?)\s*\((\d{4})\)/
        if let match = try? parenPattern.firstMatch(in: name) {
            let year = String(match.2)
            if let y = Int(year), y >= 1900 && y <= 2100 {
                let title = cleanTitle(String(match.1))
                if !title.isEmpty { return (title, year) }
            }
        }

        // "Title.YYYY." or "Title YYYY " with dots/spaces as separators
        let dotPattern = /^(.+?)[\.\s_-]+(\d{4})(?:[\.\s_-]|$)/
        if let match = try? dotPattern.firstMatch(in: name) {
            let year = String(match.2)
            if let y = Int(year), y >= 1900 && y <= 2100 {
                let title = cleanTitle(String(match.1))
                if !title.isEmpty { return (title, year) }
            }
        }

        // Fallback: first 4-digit year in range
        let yearPattern = /\b(\d{4})\b/
        for match in name.matches(of: yearPattern) {
            let year = String(match.1)
            if let y = Int(year), y >= 1900 && y <= 2100,
               let range = name.range(of: year) {
                let title = cleanTitle(String(name[name.startIndex..<range.lowerBound]))
                if !title.isEmpty { return (title, year) }
            }
        }

        return nil
    }

    nonisolated static func extractIMDBID(from input: String) -> String? {
        let pattern = /tt\d{7,}/
        guard let match = try? pattern.firstMatch(in: input) else { return nil }
        return String(match.0)
    }

    // MARK: - Lookup (nonisolated, runs off main thread)

    nonisolated static func lookupMovie(_ searchTerm: String, apiKey: String? = nil) async -> MovieInfo? {
        let key: String
        if let apiKey {
            key = apiKey
        } else {
            key = await MainActor.run { AppSettings.shared.omdbAPIKey }
        }

        let detected = detectMovie(folderName: searchTerm)
        let title = detected?.title ?? searchTerm
        let year = detected?.year ?? ""

        // Try OMDB first, then fall back to IMDB scraping
        if !key.isEmpty {
            if let info = await fetchFromOMDB(title: title, year: year, apiKey: key) {
                return info
            }
        }
        guard let imdbID = await searchForIMDBID(title: title, year: year) else { return nil }
        return await scrapeIMDB(id: imdbID)
    }

    // MARK: - OMDB

    nonisolated private static func fetchFromOMDB(title: String, year: String, apiKey: String) async -> MovieInfo? {
        // Try with year first, then without
        if let info = await omdbRequest(params: "t=\(title)&y=\(year)", apiKey: apiKey) {
            return info
        }
        if !year.isEmpty {
            return await omdbRequest(params: "t=\(title)", apiKey: apiKey)
        }
        return nil
    }

    nonisolated private static func fetchFromOMDB(imdbID: String, apiKey: String) async -> MovieInfo? {
        await omdbRequest(params: "i=\(imdbID)", apiKey: apiKey)
    }

    nonisolated private static func omdbRequest(params: String, apiKey: String) async -> MovieInfo? {
        let encoded = params.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? params
        guard let url = URL(string: "https://www.omdbapi.com/?\(encoded)&plot=short&apikey=\(apiKey)") else { return nil }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 12
            let (data, response) = try await networkSession.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            if json["Response"] as? String == "False" { return nil }
            return parseOMDBResponse(json)
        } catch {
            return nil
        }
    }

    nonisolated private static func parseOMDBResponse(_ json: [String: Any]) -> MovieInfo? {
        guard let title = json["Title"] as? String,
              let imdbID = json["imdbID"] as? String else { return nil }

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

    // MARK: - IMDB Scraping

    nonisolated static func scrapeIMDB(id imdbID: String) async -> MovieInfo? {
        guard let url = URL(string: "https://www.imdb.com/title/\(imdbID)/") else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        do {
            let (data, _) = try await networkSession.data(for: request)
            guard let html = String(data: data, encoding: .utf8) else { return nil }
            return parseIMDBPage(html: html, imdbID: imdbID)
        } catch {
            return nil
        }
    }

    nonisolated private static func parseIMDBPage(html: String, imdbID: String) -> MovieInfo? {
        let ldPattern = /<script type="application\/ld\+json">(.*?)<\/script>/
        guard let match = try? ldPattern.firstMatch(in: html) else { return nil }
        guard let jsonData = String(match.1).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let title = json["name"] as? String else { return nil }

        let year: String
        if let dateStr = json["datePublished"] as? String, dateStr.count >= 4 {
            year = String(dateStr.prefix(4))
        } else {
            year = "N/A"
        }

        let runtime: String
        if let dur = json["duration"] as? String {
            runtime = parseISO8601Duration(dur)
        } else {
            runtime = "N/A"
        }

        let genre: String
        if let arr = json["genre"] as? [String] { genre = arr.joined(separator: ", ") }
        else if let str = json["genre"] as? String { genre = str }
        else { genre = "N/A" }

        let director: String
        if let arr = json["director"] as? [[String: Any]] {
            director = arr.compactMap { $0["name"] as? String }.joined(separator: ", ")
        } else { director = "N/A" }

        let actors: String
        if let arr = json["actor"] as? [[String: Any]] {
            actors = arr.compactMap { $0["name"] as? String }.joined(separator: ", ")
        } else { actors = "N/A" }

        let imdbRating: String
        if let agg = json["aggregateRating"] as? [String: Any], let val = agg["ratingValue"] {
            imdbRating = "\(val)"
        } else { imdbRating = "N/A" }

        return MovieInfo(
            title: title,
            year: year,
            rated: json["contentRating"] as? String ?? "N/A",
            runtime: runtime,
            genre: genre,
            director: director,
            actors: actors,
            plot: json["description"] as? String ?? "N/A",
            posterURL: json["image"] as? String ?? "N/A",
            imdbRating: imdbRating,
            imdbID: imdbID,
            type: (json["@type"] as? String ?? "Movie").lowercased()
        )
    }

    nonisolated private static func searchForIMDBID(title: String, year: String) async -> String? {
        let query = "imdb \(title) \(year)".trimmingCharacters(in: .whitespaces)
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://html.duckduckgo.com/html/?q=\(encoded)") else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        do {
            let (data, _) = try await networkSession.data(for: request)
            guard let html = String(data: data, encoding: .utf8) else { return nil }
            let pattern = /tt\d{7,}/
            guard let match = try? pattern.firstMatch(in: html) else { return nil }
            return String(match.0)
        } catch {
            return nil
        }
    }

    // MARK: - Cache (disk, alongside movie files)

    nonisolated private static func cacheFileURL(for url: URL, isDir: Bool) -> URL {
        if isDir {
            return url.appendingPathComponent(".fe-movie.json")
        } else {
            let dir = url.deletingLastPathComponent()
            return dir.appendingPathComponent(".fe-\(url.lastPathComponent).json")
        }
    }

    nonisolated private static func prepareMovieInfo(for url: URL) -> (detected: (title: String, year: String), cached: MovieInfo?, cacheFile: URL)? {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)

        let detected: (title: String, year: String)
        if isDir.boolValue {
            if let fromFolder = detectMovie(folderName: url.lastPathComponent) {
                detected = fromFolder
            } else if let videoFile = firstVideoFile(in: url),
                      let fromFile = detectMovie(folderName: videoFile.lastPathComponent) {
                detected = fromFile
            } else {
                return nil
            }
        } else {
            guard let fromFile = detectMovie(folderName: url.lastPathComponent) else { return nil }
            detected = fromFile
        }

        let cacheFile = cacheFileURL(for: url, isDir: isDir.boolValue)
        let cached = loadCache(from: cacheFile)
        return (detected, cached, cacheFile)
    }

    nonisolated private static func loadCache(from url: URL) -> MovieInfo? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let info = try? JSONDecoder().decode(MovieInfo.self, from: data) { return info }
        try? FileManager.default.removeItem(at: url)
        return nil
    }

    nonisolated private static func saveCache(_ info: MovieInfo, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(info) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - Helpers

    nonisolated private static func cleanTitle(_ raw: String) -> String {
        var title = raw
        title = title.replacingOccurrences(of: ".", with: " ")
        title = title.replacingOccurrences(of: "_", with: " ")
        title = title.replacingOccurrences(of: "-", with: " ")

        let removals = [
            "1080p", "720p", "2160p", "4k", "uhd", "hdr",
            "bluray", "blu ray", "brrip", "bdrip", "dvdrip",
            "webrip", "web dl", "hdtv", "x264", "x265", "h264", "h265",
            "aac", "dts", "ac3", "remux", "repack", "proper",
            "extended", "directors cut", "unrated", "theatrical"
        ]
        let lower = title.lowercased()
        for tag in removals {
            if let range = lower.range(of: tag) {
                title = String(title[title.startIndex..<range.lowerBound])
            }
        }
        return title.trimmingCharacters(in: .whitespaces)
    }

    nonisolated private static func parseISO8601Duration(_ dur: String) -> String {
        var result = ""
        if let h = try? /(\d+)H/.firstMatch(in: dur) { result += "\(h.1)h " }
        if let m = try? /(\d+)M/.firstMatch(in: dur) { result += "\(m.1) min" }
        let trimmed = result.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "N/A" : trimmed
    }
}
