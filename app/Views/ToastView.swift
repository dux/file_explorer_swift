import SwiftUI

@MainActor
class ToastManager: ObservableObject {
    static let shared = ToastManager()

    @Published var message: String = ""
    @Published var isShowing: Bool = false

    private var hideTask: DispatchWorkItem?

    func show(_ message: String, duration: Double = 2.0) {
        hideTask?.cancel()

        self.message = message
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
                .background(Color.black.opacity(0.75))
                .cornerRadius(8)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }
}
