import AppKit
import UserNotifications

/// Posts standard macOS notification banners for due reminders, with Done / Snooze actions.
final class NotificationService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let categoryID = "NUDGE_REMINDER"
    static let doneAction = "NUDGE_DONE"
    static let snoozeAction = "NUDGE_SNOOZE"

    /// Called with the todo id and the action the user picked on the banner.
    var onAction: ((UUID, AttentionAction) -> Void)?
    /// Called when the banner itself is clicked.
    var onOpen: ((UUID) -> Void)?

    @Published private(set) var authorized: Bool? = nil

    /// UNUserNotificationCenter aborts when the process has no bundle identifier (bare executable).
    private var available: Bool { Bundle.main.bundleIdentifier != nil }

    func setup() {
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let done = UNNotificationAction(identifier: Self.doneAction, title: "Mark as Done", options: [])
        let snooze = UNNotificationAction(identifier: Self.snoozeAction,
                                          title: "Snooze \(AppSettings.shared.snoozeMinutes.first?.minutesLabel ?? "5 min")",
                                          options: [])
        let category = UNNotificationCategory(identifier: Self.categoryID, actions: [done, snooze],
                                              intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
        refreshAuthorization()
    }

    func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        guard available else { completion?(false); return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.authorized = granted
                completion?(granted)
            }
        }
    }

    func refreshAuthorization() {
        guard available else { return }
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] s in
            DispatchQueue.main.async {
                switch s.authorizationStatus {
                case .authorized, .provisional: self?.authorized = true
                case .denied: self?.authorized = false
                default: self?.authorized = nil
                }
            }
        }
    }

    func post(todo: Todo) {
        guard available else { return }
        let content = UNMutableNotificationContent()
        content.title = todo.title
        var lines: [String] = []
        if !todo.notes.isEmpty { lines.append(todo.notes) }
        if let when = todo.reminderAt { lines.append(when.reminderDescription) }
        if todo.repeats { lines.append("Repeats · \(todo.repeatRule.shortLabel)") }
        content.body = lines.joined(separator: "\n")
        content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: "\(AppSettings.shared.chimeSound).aiff"))
        content.categoryIdentifier = Self.categoryID
        content.userInfo = ["todoID": todo.id.uuidString]
        content.interruptionLevel = .active

        let request = UNNotificationRequest(identifier: todo.id.uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { NSLog("Nudge: notification failed: \(error.localizedDescription)") }
        }
    }

    func remove(todoID: UUID) {
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [todoID.uuidString])
        center.removePendingNotificationRequests(withIdentifiers: [todoID.uuidString])
    }

    // MARK: UNUserNotificationCenterDelegate

    /// Show the banner even while Nudge is the frontmost app.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        defer { completionHandler() }
        guard let raw = response.notification.request.content.userInfo["todoID"] as? String,
              let id = UUID(uuidString: raw) else { return }

        switch response.actionIdentifier {
        case Self.doneAction:
            onAction?(id, .done)
        case Self.snoozeAction:
            let minutes = AppSettings.shared.snoozeMinutes.first ?? 5
            onAction?(id, .snooze(TimeInterval(minutes * 60)))
        case UNNotificationDismissActionIdentifier:
            onAction?(id, .dismiss)
        default:
            onOpen?(id)
        }
    }
}
