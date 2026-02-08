import SwiftUI

// MARK: - Text Styles
// Use like CSS classes: Text("Hello").textStyle(.default)
// Sizes are configurable in Settings > Font Sizes

enum TextStyle {
    /// File/folder names in center view, list items, context menus — 14pt default
    case `default`
    /// All buttons, action items, detail values, breadcrumbs, toast — 13pt medium
    case buttons
    /// Secondary info, metadata, captions, sidebar paths — 11pt
    case small
    /// Section headers like "PINNED FOLDERS", "OPEN WITH" — 12pt semibold uppercase secondary
    case title
}

private struct TextStyleModifier: ViewModifier {
    let style: TextStyle
    let weight: Font.Weight?
    let mono: Bool
    @ObservedObject private var settings = AppSettings.shared

    private var resolvedSize: CGFloat {
        switch style {
        case .default: return settings.fontDefault
        case .buttons: return settings.fontButtons
        case .small: return settings.fontSmall
        case .title: return settings.fontTitle
        }
    }

    private var resolvedWeight: Font.Weight {
        if let weight { return weight }
        switch style {
        case .default: return .regular
        case .buttons: return .medium
        case .small: return .regular
        case .title: return .semibold
        }
    }

    private var resolvedFont: Font {
        .system(size: resolvedSize, weight: resolvedWeight, design: mono ? .monospaced : .default)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if style == .title {
            content
                .font(resolvedFont)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
        } else {
            content
                .font(resolvedFont)
        }
    }
}

extension View {
    func textStyle(_ style: TextStyle, weight: Font.Weight? = nil, mono: Bool = false) -> some View {
        modifier(TextStyleModifier(style: style, weight: weight, mono: mono))
    }
}
