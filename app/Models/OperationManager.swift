import Foundation

@MainActor
final class OperationManager: ObservableObject {
    static let shared = OperationManager()

    @Published private(set) var isActive = false
    @Published private(set) var title = ""

    private var currentID: UUID?
    private var cancelHandler: (() -> Void)?

    private init() {}

    @discardableResult
    func begin(title: String, cancel: @escaping () -> Void) -> UUID {
        cancelCurrent(showToast: false)

        let id = UUID()
        currentID = id
        self.title = title
        cancelHandler = cancel
        isActive = true
        return id
    }

    func finish(_ id: UUID) {
        guard currentID == id else { return }
        currentID = nil
        cancelHandler = nil
        title = ""
        isActive = false
    }

    @discardableResult
    func cancel(_ id: UUID, showToast: Bool = true) -> Bool {
        guard currentID == id else { return false }
        return cancelCurrent(showToast: showToast)
    }

    @discardableResult
    func cancelCurrent(showToast: Bool = true) -> Bool {
        guard isActive else { return false }

        let cancel = cancelHandler
        currentID = nil
        cancelHandler = nil
        let cancelledTitle = title
        title = ""
        isActive = false

        cancel?()
        if showToast {
            ToastManager.shared.show("Cancelled \(cancelledTitle.lowercased())")
        }
        return true
    }

    /// Runs `work` off the main actor and returns its result. The cancellable
    /// "… - Esc to stop" indicator only appears if the work is still running after
    /// `showDelay` seconds, so instant operations (e.g. same-volume moves) don't
    /// flicker it. Pressing Esc cancels the underlying task (observe `Task.isCancelled`).
    @discardableResult
    func run<T: Sendable>(
        title: String,
        showDelay: Double = 0.15,
        work: @escaping @Sendable () async -> T
    ) async -> T {
        let task = Task.detached(priority: .userInitiated) { await work() }

        // Show the indicator only if the work outlives the delay.
        let indicator: Task<UUID?, Never> = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(showDelay * 1_000_000_000)) }
            catch { return nil }
            return self?.begin(title: title) { task.cancel() }
        }

        let result = await task.value
        indicator.cancel()
        if let id = await indicator.value { finish(id) }
        return result
    }
}
