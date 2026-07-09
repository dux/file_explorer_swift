import SwiftUI
import AppKit

// MARK: - Row Mouse Area (left click + multi-file drag source)

/// SwiftUI's .onDrag carries a single NSItemProvider, so it cannot drag more than
/// one file, and it promises the URL asynchronously - which pasteboard consumers
/// like browsers (Gmail), Mail or Slack reject. This overlay starts a real
/// NSDraggingSession with every URL written synchronously to the pasteboard
/// (same as Finder) and reports left clicks back with location, click count and
/// modifier flags. Right clicks fall through to RightClickableArea overlays.
struct FileRowMouseArea: NSViewRepresentable {
    let dragURLs: @MainActor () -> [URL]
    let onClick: @MainActor (CGPoint, Int, NSEvent.ModifierFlags) -> Void

    func makeNSView(context: Context) -> MouseAreaNSView {
        let view = MouseAreaNSView()
        view.dragURLs = dragURLs
        view.onClick = onClick
        return view
    }

    func updateNSView(_ nsView: MouseAreaNSView, context: Context) {
        nsView.dragURLs = dragURLs
        nsView.onClick = onClick
    }

    class MouseAreaNSView: NSView, NSDraggingSource {
        var dragURLs: (@MainActor () -> [URL])?
        var onClick: (@MainActor (CGPoint, Int, NSEvent.ModifierFlags) -> Void)?
        private var mouseDownEvent: NSEvent?

        // Leave right clicks to the RightClickableArea overlay above
        override func hitTest(_ point: NSPoint) -> NSView? {
            if let event = NSApp.currentEvent, event.type == .rightMouseDown {
                return nil
            }
            return super.hitTest(point)
        }

        override func mouseDown(with event: NSEvent) {
            mouseDownEvent = event
        }

        override func mouseDragged(with event: NSEvent) {
            guard let down = mouseDownEvent else { return }
            let dx = event.locationInWindow.x - down.locationInWindow.x
            let dy = event.locationInWindow.y - down.locationInWindow.y
            guard dx * dx + dy * dy > 16 else { return }   // 4pt drag threshold
            mouseDownEvent = nil
            beginDrag(with: down)
        }

        override func mouseUp(with event: NSEvent) {
            if mouseDownEvent != nil {
                onClick?(convert(event.locationInWindow, from: nil), event.clickCount, event.modifierFlags)
            }
            mouseDownEvent = nil
        }

        private func beginDrag(with event: NSEvent) {
            guard let urls = dragURLs?(), !urls.isEmpty else { return }
            let origin = convert(event.locationInWindow, from: nil)
            let iconSize: CGFloat = 32
            let items = urls.enumerated().map { index, url in
                let item = NSDraggingItem(pasteboardWriter: url as NSURL)
                let cascade = CGFloat(min(index, 10)) * 2
                item.setDraggingFrame(
                    NSRect(
                        x: origin.x - iconSize / 2 + cascade,
                        y: origin.y - iconSize / 2 - cascade,
                        width: iconSize,
                        height: iconSize
                    ),
                    contents: NSWorkspace.shared.icon(forFile: url.path)
                )
                return item
            }
            beginDraggingSession(with: items, event: event, source: self)
        }

        nonisolated func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            .copy
        }
    }
}
