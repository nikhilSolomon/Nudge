import AppKit

/// Polls the store once a second and surfaces any due reminder as a screen takeover,
/// a notification banner, or both (per Settings).
/// Polling (rather than one timer per reminder) survives sleep/wake and clock changes:
/// anything whose time has passed fires on the next tick.
final class ReminderScheduler {
    private let store: TodoStore
    private let overlay = AttentionOverlay()
    let notifications = NotificationService()
    private let settings = AppSettings.shared
    private var timer: Timer?

    /// Called when the user clicks a notification banner (to bring the main window forward).
    var onOpenRequested: (() -> Void)?

    init(store: TodoStore) {
        self.store = store
    }

    func start() {
        notifications.setup()
        notifications.onAction = { [weak self] id, action in
            self?.handle(action, for: id)
            if self?.overlay.isShowing == true { self?.overlay.dismiss() }
            DispatchQueue.main.async { self?.tick() }
        }
        notifications.onOpen = { [weak self] _ in
            self?.onOpenRequested?()
        }
        if settings.reminderStyle.usesNotification {
            notifications.requestAuthorization()
        }

        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    func tick() {
        guard !overlay.isShowing else { return }
        guard let due = store.nextDueToFire() else { return }
        store.markFired(due.id)

        let style = settings.reminderStyle
        if style.usesNotification {
            notifications.post(todo: due)
        }
        if style.usesOverlay {
            overlay.show(todo: due) { [weak self] action in
                guard let self else { return }
                self.handle(action, for: due.id)
                self.notifications.remove(todoID: due.id)
                self.overlay.dismiss()
                DispatchQueue.main.async { self.tick() }
            }
        } else {
            // Banner-only: keep draining anything else that is due.
            DispatchQueue.main.async { [weak self] in self?.tick() }
        }
    }

    private func handle(_ action: AttentionAction, for id: UUID) {
        switch action {
        case .done:
            store.complete(id) // repeating todos roll forward instead
        case .snooze(let interval):
            store.snooze(id, by: interval)
        case .dismiss:
            break
        }
        notifications.remove(todoID: id)
    }
}
