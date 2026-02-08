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
                packageInfoView(pkg)
            } else {
                VStack {
                    Text("Unable to parse package.json")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { loadContent() }
        .onChange(of: url) { _ in loadContent() }
    }

    private func packageInfoView(_ pkg: PackageInfo) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Package manager detection
                packageManagerBadge

                if let description = pkg.description {
                    sectionRow(icon: "text.quote", label: "Description", color: .secondary) {
                        Text(description)
                            .textStyle(.default)
                            .foregroundColor(.primary)
                    }
                }

                if let license = pkg.license {
                    sectionRow(icon: "doc.text", label: "License", color: .blue) {
                        Text(license)
                            .textStyle(.default, mono: true)
                    }
                }

                if let main = pkg.main {
                    sectionRow(icon: "arrow.right.circle", label: "Entry", color: .purple) {
                        Text(main)
                            .textStyle(.default, mono: true)
                    }
                }

                if let type = pkg.type {
                    sectionRow(icon: "cube", label: "Type", color: .indigo) {
                        Text(type)
                            .textStyle(.default, mono: true)
                    }
                }

                if let engines = pkg.engines, !engines.isEmpty {
                    sectionRow(icon: "gearshape.2", label: "Engines", color: .gray) {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(engines.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                                HStack(spacing: 4) {
                                    Text(key)
                                        .textStyle(.default, weight: .medium, mono: true)
                                    Text(value)
                                        .textStyle(.default, mono: true)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }

                // Scripts
                if let scripts = pkg.scripts, !scripts.isEmpty {
                    scriptSection(scripts)
                }

                // Dependencies
                if let deps = pkg.dependencies, !deps.isEmpty {
                    depSection(title: "Dependencies", deps: deps, color: .green, icon: "cube.fill", count: deps.count)
                }

                if let devDeps = pkg.devDependencies, !devDeps.isEmpty {
                    depSection(title: "Dev Dependencies", deps: devDeps, color: .orange, icon: "hammer.fill", count: devDeps.count)
                }

                if let peerDeps = pkg.peerDependencies, !peerDeps.isEmpty {
                    depSection(title: "Peer Dependencies", deps: peerDeps, color: .purple, icon: "link", count: peerDeps.count)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Package Manager Detection

    private var packageManagerBadge: some View {
        let pm = detectPackageManager()
        return HStack(spacing: 8) {
            Image(systemName: pm.icon)
                .textStyle(.default)
                .foregroundColor(pm.color)
            Text(pm.name)
                .textStyle(.default, weight: .medium)
                .foregroundColor(pm.color)

            if let pmField = pkg?.packageManager {
                Text(pmField)
                    .textStyle(.buttons, mono: true)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(pm.color.opacity(0.06))
    }

    private func detectPackageManager() -> (name: String, icon: String, color: Color) {
        let dir = url.deletingLastPathComponent()
        let fm = FileManager.default

        // Check packageManager field first
        if let pmField = pkg?.packageManager {
            let lower = pmField.lowercased()
            if lower.hasPrefix("pnpm") { return ("pnpm", "p.circle.fill", .orange) }
            if lower.hasPrefix("yarn") { return ("Yarn", "y.circle.fill", .blue) }
            if lower.hasPrefix("bun") { return ("Bun", "b.circle.fill", .pink) }
            if lower.hasPrefix("npm") { return ("npm", "n.circle.fill", .red) }
        }

        // Check lock files
        if fm.fileExists(atPath: dir.appendingPathComponent("bun.lockb").path) ||
           fm.fileExists(atPath: dir.appendingPathComponent("bun.lock").path) {
            return ("Bun", "b.circle.fill", .pink)
        }
        if fm.fileExists(atPath: dir.appendingPathComponent("pnpm-lock.yaml").path) {
            return ("pnpm", "p.circle.fill", .orange)
        }
        if fm.fileExists(atPath: dir.appendingPathComponent("yarn.lock").path) {
            return ("Yarn", "y.circle.fill", .blue)
        }
        if fm.fileExists(atPath: dir.appendingPathComponent("package-lock.json").path) {
            return ("npm", "n.circle.fill", .red)
        }

        return ("npm", "n.circle.fill", .red)
    }

    // MARK: - Sections

    private func sectionRow<Content: View>(icon: String, label: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .textStyle(.buttons)
                .foregroundColor(color)
                .frame(width: 18, alignment: .center)

            Text(label)
                .textStyle(.default, weight: .medium)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)

            content()

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private func scriptSection(_ scripts: [String: String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "terminal.fill")
                    .textStyle(.default)
                    .foregroundColor(.cyan)
                Text("Scripts")
                    .textStyle(.default, weight: .semibold)
                Text("(\(scripts.count))")
                    .textStyle(.buttons)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 4)

            ForEach(scripts.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                HStack(alignment: .top, spacing: 6) {
                    Text(key)
                        .textStyle(.default, weight: .medium, mono: true)
                        .foregroundColor(.cyan)
                        .frame(minWidth: 80, alignment: .trailing)

                    Text(value)
                        .textStyle(.default, mono: true)
                        .foregroundColor(.primary.opacity(0.8))
                        .lineLimit(2)
                        .textSelection(.enabled)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 3)
            }
        }
    }

    private func depSection(title: String, deps: [String: String], color: Color, icon: String, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .textStyle(.default)
                    .foregroundColor(color)
                Text(title)
                    .textStyle(.default, weight: .semibold)
                Text("(\(count))")
                    .textStyle(.buttons)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 4)

            ForEach(deps.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                HStack(spacing: 6) {
                    Text(key)
                        .textStyle(.default, mono: true)
                        .foregroundColor(.primary)

                    Spacer(minLength: 0)

                    Text(value)
                        .textStyle(.default, mono: true)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Load & Parse

    private func loadContent() {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            rawContent = "Unable to load file"
            pkg = nil
            return
        }

        // Format raw JSON
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
