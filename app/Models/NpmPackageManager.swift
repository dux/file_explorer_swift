import Foundation

struct NpmPackageInfo: Equatable {
    let webURL: URL
    let displayLabel: String
    let packageName: String
    let packageRoot: URL
}

@MainActor
class NpmPackageManager: ObservableObject {
    @Published var npmPackageInfo: NpmPackageInfo?

    static let shared = NpmPackageManager()

    private var cachedRoot: URL?
    private var cachedInfo: NpmPackageInfo?

    private init() {}

    func update(for path: URL) {
        guard let packageRoot = findPackageRoot(from: path) else {
            npmPackageInfo = nil
            cachedRoot = nil
            cachedInfo = nil
            return
        }

        // Cache hit - same package root, skip re-parse
        if let cached = cachedRoot, cached.path == packageRoot.path {
            npmPackageInfo = cachedInfo
            return
        }

        cachedRoot = packageRoot
        cachedInfo = parsePackageJSON(packageRoot: packageRoot)
        npmPackageInfo = cachedInfo
    }

    private func findPackageRoot(from path: URL) -> URL? {
        var current = path.standardizedFileURL
        let root = URL(fileURLWithPath: "/")

        while current.path != root.path {
            let packageJSON = current.appendingPathComponent("package.json")
            if FileManager.default.fileExists(atPath: packageJSON.path) {
                return current
            }
            current = current.deletingLastPathComponent()
        }
        return nil
    }

    private func parsePackageJSON(packageRoot: URL) -> NpmPackageInfo? {
        let packageFile = packageRoot.appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: packageFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = json["name"] as? String,
              !name.isEmpty else {
            return nil
        }

        // Only show link if package has a name that looks publishable
        // Skip private packages unless they have a homepage
        let isPrivate = json["private"] as? Bool ?? false

        // Use homepage if defined, otherwise npmjs.com
        if let homepage = json["homepage"] as? String,
           !homepage.isEmpty,
           let homepageURL = URL(string: homepage) {
            let label = "Go to NPM package home"
            return NpmPackageInfo(
                webURL: homepageURL,
                displayLabel: label,
                packageName: name,
                packageRoot: packageRoot
            )
        }

        // Skip private packages with no homepage
        if isPrivate { return nil }

        // Build npmjs.com URL
        guard let webURL = URL(string: "https://www.npmjs.com/package/\(name)") else { return nil }

        let label = "Go to NPM package home"
        return NpmPackageInfo(
            webURL: webURL,
            displayLabel: label,
            packageName: name,
            packageRoot: packageRoot
        )
    }
}
