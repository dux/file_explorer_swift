import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Drop Helpers

/// Collects file URLs from drop providers, deduplicates, then calls back on main with unique URLs.
func collectDropURLs(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
    let collector = URLCollector()
    let group = DispatchGroup()

    for provider in providers {
        group.enter()
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
            defer { group.leave() }
            guard let data = data as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            collector.add(url)
        }
    }

    group.notify(queue: .main) {
        completion(collector.uniqueURLs)
    }
}

private final class URLCollector: @unchecked Sendable {
    private var urls: [URL] = []
    private let lock = NSLock()

    func add(_ url: URL) {
        lock.lock()
        urls.append(url)
        lock.unlock()
    }

    var uniqueURLs: [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.path).inserted }
    }
}

// MARK: - Shared Utility Functions

func formatDateShort(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
}

func calculateFileSize(url: URL, isDirectory: Bool, completion: @MainActor @escaping (String, Int?) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
        if isDirectory {
            var totalSize: UInt64 = 0
            var count = 0
            if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: []) {
                for case let fileURL as URL in enumerator {
                    count += 1
                    if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                        totalSize += UInt64(size)
                    }
                }
            }
            let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(totalSize), countStyle: .file)
            DispatchQueue.main.async {
                completion(sizeStr, count)
            }
        } else {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? UInt64 {
                let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
                DispatchQueue.main.async {
                    completion(sizeStr, nil)
                }
            }
        }
    }
}

// MARK: - Sheet Header

struct SheetHeader: View {
    let icon: String
    let title: String
    var color: Color = .accentColor
    @Binding var isPresented: Bool

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(color)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            SheetCloseButton(isPresented: $isPresented)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - Sheet Close Button

struct SheetCloseButton: View {
    @Binding var isPresented: Bool

    var body: some View {
        Button(action: { isPresented = false }) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 18))
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sheet Footer (filename + close)

struct SheetFooter: View {
    let filename: String
    @Binding var isPresented: Bool

    var body: some View {
        HStack {
            Text(filename)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .lineLimit(1)
            Spacer()
            Button("Close") {
                isPresented = false
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - Loading State View

struct LoadingStateView: View {
    var message: String = "Loading..."

    var body: some View {
        VStack {
            ProgressView()
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Error State View

struct ErrorStateView: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundColor(.orange)
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Empty State View

struct EmptyStateView: View {
    var icon: String = "tray"
    var message: String = "Nothing here"

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Metadata Table View

struct MetadataTableView: View {
    let items: [(key: String, value: String)]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(items, id: \.key) { item in
                    HStack(alignment: .top) {
                        Text(item.key)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 140, alignment: .trailing)
                        Text(item.value)
                            .font(.system(size: 13))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    Divider()
                        .padding(.leading, 160)
                }
            }
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Font Size Controls

struct FontSizeControls: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        HStack(spacing: 4) {
            Button(action: { settings.decreaseFontSize() }) {
                Image(systemName: "minus")
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.borderless)
            Text("\(Int(settings.previewFontSize))px")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 32)
            Button(action: { settings.increaseFontSize() }) {
                Image(systemName: "plus")
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.borderless)
        }
        .padding(.trailing, 8)
    }
}

// MARK: - Drop-on-App Handler

func handleFileDrop(providers: [NSItemProvider], appURL: URL) -> Bool {
    for provider in providers {
        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
            guard let data = item as? Data,
                  let fileURL = URL(dataRepresentation: data, relativeTo: nil) else { return }
            DispatchQueue.main.async {
                NSWorkspace.shared.open([fileURL], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
            }
        }
    }
    return true
}
