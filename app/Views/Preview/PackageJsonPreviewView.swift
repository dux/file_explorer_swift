import SwiftUI

struct PackageJsonPreviewView: View {
    let url: URL
    @ObservedObject private var settings = AppSettings.shared
    @State private var pkg: PackageInfo?
    @State private var rawContent: String = ""
    @State private var showRaw: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "shippingbox.fill")
                    .textStyle(.default)
                    .foregroundColor(.green)

                if let pkg {
                    Text(pkg.name ?? "package.json")
                        .textStyle(.buttons)
                        .lineLimit(1)

                    if let version = pkg.version {
                        Text("v\(version)")
                            .textStyle(.small, weight: .medium, mono: true)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15))
                            .cornerRadius(4)
                    }
                } else {
                    Text("package.json")
                        .textStyle(.buttons)
                        .lineLimit(1)
                }

                Spacer()

                Button(action: { showRaw.toggle() }) {
                    HStack(spacing: 4) {
                        Image(systemName: showRaw ? "list.bullet" : "curlybraces")
                            .textStyle(.small)
                        Text(showRaw ? "Info" : "Raw")
                            .textStyle(.small)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)

                if showRaw {
                    FontSizeControls(settings: settings)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            if showRaw {
                SyntaxHighlightView(code: rawContent, language: "json", fontSize: settings.previewFontSize)
            } else if let pkg {
                HTMLPreviewView(bodyHTML: packageInfoHTML(pkg), extraCSS: Self.infoCSS)
            } else {
                VStack {
                    Text("Unable to parse package.json")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: url) { await loadContent() }
    }

    // MARK: - Info HTML

    private static let infoCSS = """
    body { padding: 0 0 12px; }
    .pm { display: flex; align-items: center; gap: 6px; padding: 10px 16px; background: rgba(127,127,127,0.10); color: var(--pm); font-weight: 600; }
    .pm .dot { width: 8px; height: 8px; border-radius: 50%; background: var(--pm); display: inline-block; }
    .row { display: flex; gap: 10px; padding: 6px 16px; align-items: baseline; }
    .row .label { color: #888; font-weight: 600; min-width: 80px; flex-shrink: 0; }
    .row .val { flex: 1; word-break: break-word; }
    .section { padding: 12px 16px 4px; font-weight: 600; }
    .section .dim { font-weight: 400; }
    .kvrow { display: flex; gap: 10px; padding: 2px 16px; }
    .kvrow .k { min-width: 110px; flex-shrink: 0; }
    .kvrow .v { flex: 1; opacity: 0.8; word-break: break-word; }
    .mono { font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, monospace; font-size: 12px; }
    .dim { opacity: 0.65; }
    """

    private func packageInfoHTML(_ pkg: PackageInfo) -> String {
        let esc = HTMLPreviewView.escape
        let pm = detectPackageManager()

        func row(_ label: String, _ value: String, mono: Bool = false) -> String {
            "<div class=\"row\"><span class=\"label\">\(esc(label))</span><span class=\"val\(mono ? " mono" : "")\">\(esc(value))</span></div>"
        }

        var html = ""

        var pmExtra = ""
        if let pmField = pkg.packageManager { pmExtra = " <span class=\"mono dim\">\(esc(pmField))</span>" }
        html += "<div class=\"pm\" style=\"--pm:\(pm.color)\"><span class=\"dot\"></span>\(esc(pm.name))\(pmExtra)</div>"

        if let description = pkg.description { html += row("Description", description) }
        if let license = pkg.license { html += row("License", license, mono: true) }
        if let main = pkg.main { html += row("Entry", main, mono: true) }
        if let type = pkg.type { html += row("Type", type, mono: true) }

        if let engines = pkg.engines, !engines.isEmpty {
            let items = engines.sorted { $0.key < $1.key }
                .map { "<div><span class=\"mono\">\(esc($0.key))</span> <span class=\"mono dim\">\(esc($0.value))</span></div>" }
                .joined()
            html += "<div class=\"row\"><span class=\"label\">Engines</span><span class=\"val\">\(items)</span></div>"
        }

        if let scripts = pkg.scripts, !scripts.isEmpty {
            html += sectionHeaderHTML("Scripts", scripts.count, accent: "#26a5c4")
            for (key, value) in scripts.sorted(by: { $0.key < $1.key }) {
                html += "<div class=\"kvrow\"><span class=\"k mono\" style=\"color:#26a5c4\">\(esc(key))</span><span class=\"v mono\">\(esc(value))</span></div>"
            }
        }

        html += depBlockHTML("Dependencies", pkg.dependencies, accent: "#2ea043")
        html += depBlockHTML("Dev Dependencies", pkg.devDependencies, accent: "#d29922")
        html += depBlockHTML("Peer Dependencies", pkg.peerDependencies, accent: "#a371f7")

        return html
    }

    private func sectionHeaderHTML(_ title: String, _ count: Int, accent: String) -> String {
        "<div class=\"section\" style=\"color:\(accent)\">\(HTMLPreviewView.escape(title)) <span class=\"dim\">(\(count))</span></div>"
    }

    private func depBlockHTML(_ title: String, _ deps: [String: String]?, accent: String) -> String {
        guard let deps, !deps.isEmpty else { return "" }
        var html = sectionHeaderHTML(title, deps.count, accent: accent)
        for (key, value) in deps.sorted(by: { $0.key < $1.key }) {
            html += "<div class=\"kvrow\"><span class=\"k mono\">\(HTMLPreviewView.escape(key))</span><span class=\"v mono dim\">\(HTMLPreviewView.escape(value))</span></div>"
        }
        return html
    }

    private func detectPackageManager() -> (name: String, color: String) {
        let dir = url.deletingLastPathComponent()
        let fm = FileManager.default

        // Check packageManager field first
        if let pmField = pkg?.packageManager {
            let lower = pmField.lowercased()
            if lower.hasPrefix("pnpm") { return ("pnpm", "#f69220") }
            if lower.hasPrefix("yarn") { return ("Yarn", "#2188b6") }
            if lower.hasPrefix("bun") { return ("Bun", "#e94aa0") }
            if lower.hasPrefix("npm") { return ("npm", "#cb3837") }
        }

        // Check lock files
        if fm.fileExists(atPath: dir.appendingPathComponent("bun.lockb").path) ||
           fm.fileExists(atPath: dir.appendingPathComponent("bun.lock").path) {
            return ("Bun", "#e94aa0")
        }
        if fm.fileExists(atPath: dir.appendingPathComponent("pnpm-lock.yaml").path) {
            return ("pnpm", "#f69220")
        }
        if fm.fileExists(atPath: dir.appendingPathComponent("yarn.lock").path) {
            return ("Yarn", "#2188b6")
        }
        if fm.fileExists(atPath: dir.appendingPathComponent("package-lock.json").path) {
            return ("npm", "#cb3837")
        }

        return ("npm", "#cb3837")
    }

    // MARK: - Load & Parse

    private func loadContent() async {
        guard let text = await readFileText(url) else {
            rawContent = "Unable to load file"
            pkg = nil
            return
        }

        // Format raw JSON (package.json is small, so parsing on main is fine)
        if let data = text.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data),
           let formatted = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
           let result = String(data: formatted, encoding: .utf8) {
            rawContent = result
        } else {
            rawContent = String(text.prefix(100000))
        }

        // Parse structured data
        if let data = text.data(using: .utf8) {
            pkg = try? JSONDecoder().decode(PackageInfo.self, from: data)
        }
    }
}

// MARK: - Model

private struct PackageInfo: Decodable {
    let name: String?
    let version: String?
    let description: String?
    let main: String?
    let module: String?
    let type: String?
    let license: String?
    let packageManager: String?
    let engines: [String: String]?
    let scripts: [String: String]?
    let dependencies: [String: String]?
    let devDependencies: [String: String]?
    let peerDependencies: [String: String]?

    enum CodingKeys: String, CodingKey {
        case name, version, description, main, module, type, license
        case packageManager
        case engines, scripts, dependencies, devDependencies, peerDependencies
    }
}
