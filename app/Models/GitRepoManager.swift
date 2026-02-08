import Foundation

struct GitRepoInfo: Equatable {
    let webURL: URL
    let displayLabel: String
    let serviceName: String
    let repoPath: String
    let gitRoot: URL
}

@MainActor
class GitRepoManager: ObservableObject {
    @Published var gitRepoInfo: GitRepoInfo?

    static let shared = GitRepoManager()

    private var cachedGitRoot: URL?
    private var cachedInfo: GitRepoInfo?

    private let knownHosts: [String: String] = [
        "github.com": "GitHub",
        "gitlab.com": "GitLab",
        "bitbucket.org": "Bitbucket",
        "codeberg.org": "Codeberg",
        "sr.ht": "SourceHut"
    ]

    private init() {}

    func update(for path: URL) {
        guard let gitRoot = findGitRoot(from: path) else {
            gitRepoInfo = nil
            cachedGitRoot = nil
            cachedInfo = nil
            return
        }

        // Cache hit - same repo, skip re-parse
        if let cached = cachedGitRoot, cached.path == gitRoot.path {
            gitRepoInfo = cachedInfo
            return
        }

        cachedGitRoot = gitRoot
        cachedInfo = parseGitConfig(gitRoot: gitRoot)
        gitRepoInfo = cachedInfo
    }

    private func findGitRoot(from path: URL) -> URL? {
        var current = path.standardizedFileURL
        let root = URL(fileURLWithPath: "/")

        while current.path != root.path {
            let gitDir = current.appendingPathComponent(".git")
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: gitDir.path, isDirectory: &isDir) {
                return current
            }
            current = current.deletingLastPathComponent()
        }
        return nil
    }

    private func parseGitConfig(gitRoot: URL) -> GitRepoInfo? {
        let gitDir = gitRoot.appendingPathComponent(".git")
        var configPath = gitDir.appendingPathComponent("config")

        // Handle .git file (submodules/worktrees) - it contains "gitdir: <path>"
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: gitDir.path, isDirectory: &isDir)
        if !isDir.boolValue {
            guard let content = try? String(contentsOf: gitDir, encoding: .utf8) else { return nil }
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("gitdir: ") {
                let relPath = String(trimmed.dropFirst("gitdir: ".count))
                let resolvedDir: URL
                if relPath.hasPrefix("/") {
                    resolvedDir = URL(fileURLWithPath: relPath)
                } else {
                    resolvedDir = gitRoot.appendingPathComponent(relPath).standardized
                }
                configPath = resolvedDir.appendingPathComponent("config")
            } else {
                return nil
            }
        }

        guard let configContent = try? String(contentsOf: configPath, encoding: .utf8) else { return nil }
        guard let remoteURL = parseRemoteOriginURL(from: configContent) else { return nil }
        return buildInfo(remoteURL: remoteURL, gitRoot: gitRoot)
    }

    private func parseRemoteOriginURL(from config: String) -> String? {
        let lines = config.components(separatedBy: .newlines)
        var inOriginSection = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("[") {
                inOriginSection = trimmed.lowercased().hasPrefix("[remote \"origin\"]")
                continue
            }

            if inOriginSection && trimmed.lowercased().hasPrefix("url") {
                let parts = trimmed.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    return String(parts[1]).trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return nil
    }

    private func buildInfo(remoteURL: String, gitRoot: URL) -> GitRepoInfo? {
        guard let (host, repoPath) = parseRemoteURL(remoteURL) else { return nil }
        guard let webURL = URL(string: "https://\(host)/\(repoPath)") else { return nil }

        let serviceName: String
        if let known = knownHosts[host.lowercased()] {
            serviceName = known
        } else {
            serviceName = "git \(host)"
        }

        let displayLabel = "Go to \(serviceName) Home (\(repoPath))"

        return GitRepoInfo(
            webURL: webURL,
            displayLabel: displayLabel,
            serviceName: serviceName,
            repoPath: repoPath,
            gitRoot: gitRoot
        )
    }

    /// Parses SSH and HTTPS remote URLs into (host, repoPath)
    /// Handles:
    ///   git@github.com:user/repo.git
    ///   https://github.com/user/repo.git
    ///   ssh://git@github.com/user/repo.git
    ///   ssh://git@github.com:22/user/repo.git
    private func parseRemoteURL(_ raw: String) -> (String, String)? {
        var url = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip .git suffix
        if url.hasSuffix(".git") {
            url = String(url.dropLast(4))
        }

        // SSH shorthand: git@host:user/repo
        if url.contains("@") && url.contains(":") && !url.contains("://") {
            let atParts = url.split(separator: "@", maxSplits: 1)
            if atParts.count == 2 {
                let hostAndPath = String(atParts[1])
                let colonParts = hostAndPath.split(separator: ":", maxSplits: 1)
                if colonParts.count == 2 {
                    let host = String(colonParts[0])
                    let path = String(colonParts[1])
                    return (host, path.hasPrefix("/") ? String(path.dropFirst()) : path)
                }
            }
            return nil
        }

        // ssh://git@host/path or ssh://git@host:port/path
        if url.hasPrefix("ssh://") {
            url = String(url.dropFirst("ssh://".count))
            // Remove user@ prefix
            if let atIdx = url.firstIndex(of: "@") {
                url = String(url[url.index(after: atIdx)...])
            }
            // Remove port if present (host:port/path)
            if let colonIdx = url.firstIndex(of: ":"),
               let slashIdx = url.firstIndex(of: "/"),
               colonIdx < slashIdx {
                let host = String(url[url.startIndex..<colonIdx])
                let path = String(url[slashIdx...]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                return (host, path)
            }
            // host/path
            if let slashIdx = url.firstIndex(of: "/") {
                let host = String(url[url.startIndex..<slashIdx])
                let path = String(url[url.index(after: slashIdx)...])
                return (host, path)
            }
            return nil
        }

        // https:// or http://
        if url.hasPrefix("https://") || url.hasPrefix("http://") {
            guard let parsed = URL(string: url),
                  let host = parsed.host else { return nil }
            var path = parsed.path
            if path.hasPrefix("/") {
                path = String(path.dropFirst())
            }
            if path.isEmpty { return nil }
            return (host, path)
        }

        return nil
    }
}
