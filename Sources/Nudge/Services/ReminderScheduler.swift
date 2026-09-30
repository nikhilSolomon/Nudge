import AppKit

/// Polls the store once a second and surfaces any due reminder as a screen takeover,
/// a notification banner, or both (per Settings).
/// Polling (rather than one timer per reminder) survives sleep/wake and clock changes:
/// anything whose time has passed fires on the next tick.
final class ReminderScheduler {
    private let store: TodoStore
    private let overlay = AttentionOverlay()
    private let system = SystemStateMonitor()
    let notifications = NotificationService()
    private let settings = AppSettings.shared
    private var timer: Timer?

    /// Todo currently shown in the overlay, if any.
    private var currentTodoID: UUID?
    /// Todos that already got a banner while the screen was locked/asleep, so we don't re-post on unlock.
    private var notifiedWhileUnavailable = Set<UUID>()

    /// Called when the user clicks a notification banner (to bring the main window forward).
    var onOpenRequested: (() -> Void)?

    init(store: TodoStore) {
        self.store = store
    }

    func start() {
        notifications.setup()
        notifications.onAction = { [weak self] id, action in
            guard let self else { return }
            self.handle(action, for: id)
            if self.currentTodoID == id, self.overlay.isShowing {
                self.overlay.dismiss()
                self.currentTodoID = nil
            }
            DispatchQueue.main.async { self.tick() }
        }
        notifications.onOpen = { [weak self] _ in
            self?.onOpenRequested?()
        }
        if settings.reminderStyle.usesNotification {
            notifications.requestAuthorization()
        }

        // Lock / sleep: take the overlay down and re-arm the todo. Unlock / wake: fire again shortly.
        system.onBecameUnavailable = { [weak self] in self?.suspendOverlay() }
        system.onBecameAvailable = { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self?.tick() }
        }

        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    func tick() {
        guard !overlay.isShowing else { return }

        // Screen locked, asleep or screensaver: only banners (they show on the lock screen).
        // Leave the todos "due" so the overlay fires as soon as the screen is usable again.
        guard system.canShowOverlay else {
            if settings.reminderStyle.usesNotification {
                for todo in store.dueToFire() where !notifiedWhileUnavailable.contains(todo.id) {
                    notifications.post(todo: todo)
                    notifiedWhileUnavailable.insert(todo.id)
                }
            }
            return
        }

        guard let due = store.nextDueToFire() else { return }
        store.markFired(due.id)

        let style = settings.reminderStyle
        if style.usesNotification && !notifiedWhileUnavailable.contains(due.id) {
            notifications.post(todo: due)
        }
        notifiedWhileUnavailable.remove(due.id)

        if style.usesOverlay {
            currentTodoID = due.id
            overlay.show(todo: due) { [weak self] action in
                guard let self else { return }
                self.handle(action, for: due.id)
                self.overlay.dismiss()
                self.currentTodoID = nil
                DispatchQueue.main.async { self.tick() }
            }
        } else {
            // Banner-only: keep draining anything else that is due.
            DispatchQueue.main.async { [weak self] in self?.tick() }
        }
    }

    /// Screen just locked or went to sleep while the overlay was up: tear it down and make the
    /// todo due again so the user gets the full-screen nudge after unlocking.
    private func suspendOverlay() {
        guard overlay.isShowing, let id = currentTodoID else { return }
        overlay.dismiss()
        currentTodoID = nil
        store.resetFired(id)
        notifiedWhileUnavailable.insert(id) // its banner is already in Notification Centre
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
        notifiedWhileUnavailable.remove(id)
        notifications.remove(todoID: id)
    }
}
