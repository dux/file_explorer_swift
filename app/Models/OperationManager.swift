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
}
