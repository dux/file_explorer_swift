import SwiftUI
import AppKit

struct AppSelectorSheet: View {
    let targetURL: URL
    let fileType: String
    @ObservedObject var settings: AppSettings
    @Binding var isPresented: Bool

    @State private var searchText = ""
    @State private var filteredApps: [AppInfo] = []
    @State private var isLoading = true
    @State private var selectedIndex: Int = -1
    @State private var isListFocused = false
    @State private var searchFieldRef: NSTextField? = nil

    private let searcher = AppSearcher.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Open with...")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(12)

            Divider()

            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                SearchFieldWrapper(
                    text: $searchText,
                    fieldRef: $searchFieldRef,
                    placeholder: "Filter apps...",
                    onTextChange: { newText in
                        filteredApps = searcher.search(newText)
                        selectedIndex = filteredApps.isEmpty ? -1 : 0
                    },
                    onSubmit: {
                        if !filteredApps.isEmpty {
                            let idx = selectedIndex >= 0 && selectedIndex < filteredApps.count ? selectedIndex : 0
                            openWithApp(filteredApps[idx])
                        }
                    }
                )
                .frame(height: 22)
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        searchFieldRef?.stringValue = ""
                        filteredApps = searcher.search("")
                        selectedIndex = filteredApps.isEmpty ? -1 : 0
                        searchFieldRef?.window?.makeFirstResponder(searchFieldRef)
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color(NSColor.textBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 0)
                    .stroke(!isListFocused ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 2)
            )

            Divider()

            // App list
            if isLoading {
                Spacer()
                ProgressView()
                    .scaleEffect(0.8)
                Text("Loading apps...")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
                Spacer()
            } else if filteredApps.isEmpty {
                Spacer()
                Text("No apps found")
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(filteredApps.enumerated()), id: \.element.url.path) { idx, app in
                                AppRow(app: app, isSelected: isListFocused && selectedIndex == idx) {
                                    openWithApp(app)
                                }
                                .id(app.url.path)
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: selectedIndex) { newIdx in
                        if isListFocused && newIdx >= 0 && newIdx < filteredApps.count {
                            proxy.scrollTo(filteredApps[newIdx].url.path, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(width: 350, height: 450)
        .background(Color(NSColor.controlBackgroundColor))
        .background(AppSelectorKeyHandler(
            isListFocused: $isListFocused,
            selectedIndex: $selectedIndex,
            searchText: $searchText,
            searchFieldRef: $searchFieldRef,
            itemCount: filteredApps.count,
            onActivate: {
                guard selectedIndex >= 0 && selectedIndex < filteredApps.count else { return }
                openWithApp(filteredApps[selectedIndex])
            },
            onClose: {
                isPresented = false
            }
        ))
        .onAppear {
            loadApps()
        }
        .onChange(of: isListFocused) { focused in
            if !focused {
                searchFieldRef?.window?.makeFirstResponder(searchFieldRef)
            }
        }
    }

    private func openWithApp(_ app: AppInfo) {
        settings.addPreferredApp(for: fileType, appPath: app.url.path)
        NSWorkspace.shared.open([targetURL], withApplicationAt: app.url, configuration: NSWorkspace.OpenConfiguration())
        isPresented = false
    }

    private func loadApps() {
        isLoading = true
        searcher.loadAll {
            filteredApps = searcher.search(searchText)
            isLoading = false
        }
    }
}

// MARK: - NSTextField wrapper with direct reference

struct SearchFieldWrapper: NSViewRepresentable {
    @Binding var text: String
    @Binding var fieldRef: NSTextField?
    var placeholder: String
    var onTextChange: ((String) -> Void)?
    var onSubmit: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = placeholder
        field.isBordered = false
        field.drawsBackground = false
        field.font = .systemFont(ofSize: 14)
        field.focusRingType = .none
        field.delegate = context.coordinator
        DispatchQueue.main.async {
            self.fieldRef = field
            field.window?.makeFirstResponder(field)
        }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onTextChange = onTextChange
        context.coordinator.onSubmit = onSubmit
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onTextChange: onTextChange, onSubmit: onSubmit)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var onTextChange: ((String) -> Void)?
        var onSubmit: () -> Void

        init(text: Binding<String>, onTextChange: ((String) -> Void)?, onSubmit: @escaping () -> Void) {
            self.text = text
            self.onTextChange = onTextChange
            self.onSubmit = onSubmit
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            let value = field.stringValue
            text.wrappedValue = value
            onTextChange?(value)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                onSubmit()
                return true
            }
            return false
        }
    }
}

// MARK: - Key handler

struct AppSelectorKeyHandler: NSViewRepresentable {
    @Binding var isListFocused: Bool
    @Binding var selectedIndex: Int
    @Binding var searchText: String
    @Binding var searchFieldRef: NSTextField?
    let itemCount: Int
    let onActivate: () -> Void
    let onClose: () -> Void

    func makeNSView(context: Context) -> AppSelectorKeyView {
        let view = AppSelectorKeyView()
        view.handler = context.coordinator
        return view
    }

    func updateNSView(_ nsView: AppSelectorKeyView, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor
    class Coordinator {
        var parent: AppSelectorKeyHandler

        init(parent: AppSelectorKeyHandler) {
            self.parent = parent
        }

        nonisolated func handleKey(_ event: NSEvent) -> Bool {
            let keyCode = event.keyCode
            let listFocused = MainActor.assumeIsolated { parent.isListFocused }

            switch keyCode {
            case 48: // Tab
                MainActor.assumeIsolated {
                    parent.isListFocused.toggle()
                    if parent.isListFocused && parent.selectedIndex < 0 && parent.itemCount > 0 {
                        parent.selectedIndex = 0
                    }
                }
                return true
            case 53: // Escape
                if listFocused {
                    MainActor.assumeIsolated { parent.isListFocused = false }
                    return true
                }
                MainActor.assumeIsolated { parent.onClose() }
                return true
            default:
                break
            }

            if listFocused {
                switch keyCode {
                case 125: // Down
                    MainActor.assumeIsolated {
                        if parent.itemCount > 0 {
                            parent.selectedIndex = min(parent.selectedIndex + 1, parent.itemCount - 1)
                        }
                    }
                    return true
                case 126: // Up
                    MainActor.assumeIsolated {
                        parent.selectedIndex = max(parent.selectedIndex - 1, 0)
                    }
                    return true
                case 36: // Enter
                    MainActor.assumeIsolated { parent.onActivate() }
                    return true
                default:
                    return true
                }
            }

            return false
        }
    }
}

class AppSelectorKeyView: NSView {
    var handler: AppSelectorKeyHandler.Coordinator?
    private var monitor: Any?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil && monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if let self = self, let handler = self.handler {
                    if handler.handleKey(event) {
                        return nil
                    }
                }
                return event
            }
        } else if window == nil, let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }

    override func removeFromSuperview() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
        super.removeFromSuperview()
    }
}

struct AppRow: View {
    let app: AppInfo
    var isSelected: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: 24, height: 24)

                Text(app.name)
                    .font(.system(size: 13))
                    .foregroundColor(isSelected ? .white : .primary)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor : (isHovered ? Color.accentColor.opacity(0.15) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
