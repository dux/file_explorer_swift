import SwiftUI

struct EmojiCategory: Identifiable {
    let id: String
    let name: String
    let emojis: [String]
}

private let emojiCategories: [EmojiCategory] = [
    EmojiCategory(id: "top", name: "Top", emojis: [
        "📁", "📂", "🗂", "📦", "🏠", "🏢", "💼", "🎯", "⭐", "💡",
        "🔥", "⚡", "🚀", "💎", "🎨", "🎵", "📸", "🎬", "📝", "📚",
        "🔧", "⚙️", "🛠", "🔬", "🧪", "💻", "🖥", "📱", "🌐", "☁️",
        "🗃", "🗄", "📋", "📊", "📈", "💰", "🏷", "🔖", "📌", "📎",
        "✏️", "🖊", "🖋", "✂️", "🔑", "🔒", "🔓", "🛡", "🎪", "🎭",
        "🧩", "🎲", "♟️", "🎮", "🕹", "🤖", "👾", "🎈", "🎁", "🎀"
    ]),
    EmojiCategory(id: "dev", name: "Dev", emojis: [
        "💻", "🖥", "⌨️", "🖱", "💾", "📀", "🔌", "🔋", "📡", "🛰",
        "🐛", "🐞", "🪲", "🔧", "🛠", "⚙️", "🔩", "🧰", "📐", "📏",
        "🧮", "🔬", "🧪", "🧫", "🧬", "📊", "📈", "📉", "🗄", "🗃",
        "📋", "📝", "✅", "❌", "⚠️", "🚧", "🏗", "🔀", "🔁", "🔄",
        "▶️", "⏸", "⏹", "⏯", "🔺", "🔻", "◀️", "🔽", "🔼", "📤",
        "📥", "📨", "📧", "💬", "🗨", "🗯", "📢", "🔔", "🔕", "📣"
    ]),
    EmojiCategory(id: "work", name: "Work", emojis: [
        "💼", "📁", "📂", "🗂", "📋", "📊", "📈", "📉", "💰", "💵",
        "💳", "🏦", "🏢", "🏛", "🏫", "🎓", "📅", "📆", "🗓", "⏰",
        "⌚", "📞", "☎️", "📠", "📧", "✉️", "📨", "📩", "📮", "🗳",
        "✏️", "✒️", "🖊", "🖋", "📝", "📄", "📃", "📑", "🗒", "🗓",
        "📰", "🗞", "📓", "📔", "📒", "📕", "📗", "📘", "📙", "📚",
        "🔖", "🏷", "🔗", "📎", "🖇", "📐", "📏", "✂️", "🗑", "📌"
    ]),
    EmojiCategory(id: "nature", name: "Nature", emojis: [
        "🌳", "🌲", "🌴", "🌵", "🌿", "☘️", "🍀", "🎋", "🎍", "🍃",
        "🍂", "🍁", "🌾", "🌺", "🌻", "🌹", "🌷", "🌸", "💐", "🌼",
        "🌊", "🌈", "☀️", "🌙", "⭐", "🌟", "✨", "💫", "🌍", "🌎",
        "🍎", "🍐", "🍊", "🍋", "🍌", "🍉", "🍇", "🍓", "🫐", "🍈",
        "🍒", "🍑", "🥭", "🍍", "🥥", "🥝", "🍅", "🥑", "🥦", "🥬",
        "☕", "🍵", "🧃", "🥤", "🧋", "🍺", "🍻", "🥂", "🍷", "🍹"
    ]),
    EmojiCategory(id: "animals", name: "Animals", emojis: [
        "🐶", "🐺", "🦊", "🦝", "🐱", "🦁", "🐯", "🐆", "🐴", "🦄",
        "🦓", "🐮", "🐷", "🐗", "🐑", "🐐", "🐪", "🦒", "🐘", "🦏",
        "🦛", "🐭", "🐹", "🐰", "🐿️", "🦔", "🐻", "🐻‍❄️", "🐼", "🦥",
        "🐨", "🦘", "🐾", "🐧", "🦅", "🦉", "🦜", "🦆", "🦢", "🕊️",
        "🐸", "🐊", "🐢", "🐍", "🐉", "🦕", "🐳", "🐬", "🦈", "🐙",
        "🦋", "🐌", "🐝", "🐞"
    ]),
    EmojiCategory(id: "misc", name: "Misc", emojis: [
        "🚗", "🚕", "🚌", "🏎", "✈️", "🚀", "🛸", "⛵", "🚢", "🚲",
        "🏠", "🏡", "🏢", "🏰", "🗼", "🗽", "🏔", "🌋", "🏖", "🏝",
        "❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "🤎", "💔",
        "❤️‍🔥", "💕", "💞", "💓", "💗", "💖", "💘", "💝", "💟", "☮️",
        "🏁", "🚩", "🎌", "🏴", "🏳️", "🏳️‍🌈", "🏴‍☠️", "🇺🇸", "🇬🇧", "🇫🇷",
        "🇩🇪", "🇯🇵", "🇰🇷", "🇨🇳", "🇧🇷", "🇨🇦", "🇦🇺", "🇮🇳", "🇷🇺", "🇲🇽"
    ])
]

/// All emojis flattened + deduplicated, for search
private let allEmojis: [String] = {
    var seen = Set<String>()
    var result: [String] = []
    for cat in emojiCategories {
        for e in cat.emojis {
            if seen.insert(e).inserted {
                result.append(e)
            }
        }
    }
    return result
}()

struct EmojiPickerView: View {
    let folderURL: URL
    let onSelect: (String) -> Void
    let onRemove: () -> Void
    let onDismiss: () -> Void
    let hasExisting: Bool

    @State private var searchText = ""
    @State private var selectedTab = "top"

    private let columns = Array(repeating: GridItem(.fixed(36), spacing: 4), count: 10)

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Choose Icon")
                    .textStyle(.default, weight: .semibold)
                Spacer()
                if hasExisting {
                    Button(action: {
                        onRemove()
                        onDismiss()
                    }) {
                        Text("Remove")
                            .textStyle(.small)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .textStyle(.small)
                    .foregroundColor(.secondary)
                TextField("Search emoji...", text: $searchText)
                    .textFieldStyle(.plain)
                    .textStyle(.buttons)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .textStyle(.small)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            if searchText.isEmpty {
                // Category tabs
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(emojiCategories) { cat in
                            Button(action: { selectedTab = cat.id }) {
                                Text(cat.name)
                                    .textStyle(.small, weight: selectedTab == cat.id ? .semibold : .regular)
                                    .foregroundColor(selectedTab == cat.id ? .white : .secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(selectedTab == cat.id ? Color.accentColor : Color.gray.opacity(0.1))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.bottom, 8)
            }

            // Emoji grid
            ScrollView {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(filteredEmojis, id: \.self) { emoji in
                        Button(action: {
                            onSelect(emoji)
                            onDismiss()
                        }) {
                            Text(emoji)
                                .font(.system(size: 22))
                                .frame(width: 36, height: 36)
                                .background(Color.gray.opacity(0.05))
                                .cornerRadius(6)
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
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .frame(width: 400, height: 420)
        .background(.white)
    }

    private var filteredEmojis: [String] {
        if searchText.isEmpty {
            return emojiCategories.first { $0.id == selectedTab }?.emojis ?? []
        }
        let q = searchText.lowercased()
        return allEmojis.filter { emojiMatchesSearch($0, query: q) }
    }

    private func emojiMatchesSearch(_ emoji: String, query: String) -> Bool {
        // Search by emoji name using Unicode name property
        for scalar in emoji.unicodeScalars {
            if let name = scalar.properties.name?.lowercased(), name.contains(query) {
                return true
            }
        }
        return false
    }
}
