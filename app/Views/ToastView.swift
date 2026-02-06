import SwiftUI

enum ToastStyle {
    case info
    case error
}

@MainActor
class ToastManager: ObservableObject {
    static let shared = ToastManager()

    @Published var message: String = ""
    @Published var isShowing: Bool = false
    @Published var style: ToastStyle = .info

    private var hideTask: DispatchWorkItem?

    func show(_ message: String, duration: Double = 2.0) {
        showToast(message, style: .info, duration: duration)
    }

    func showError(_ message: String, duration: Double = 3.0) {
        showToast(message, style: .error, duration: duration)
    }

    private func showToast(_ message: String, style: ToastStyle, duration: Double) {
        hideTask?.cancel()

        self.message = message
        self.style = style
        withAnimation(.easeInOut(duration: 0.2)) {
            self.isShowing = true
        }

        let task = DispatchWorkItem { [weak self] in
            withAnimation(.easeInOut(duration: 0.2)) {
                self?.isShowing = false
            }
        }
        hideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: task)
    }
}

struct ToastView: View {
    @ObservedObject var manager = ToastManager.shared

    var body: some View {
        if manager.isShowing {
            Text(manager.message)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(manager.style == .error ? Color.red.opacity(0.85) : Color.black.opacity(0.75))
                .cornerRadius(8)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }
}
