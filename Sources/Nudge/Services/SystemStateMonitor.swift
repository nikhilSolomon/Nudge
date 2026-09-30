import AppKit

/// Tracks whether the user can actually see the screen: not locked, not asleep, no screensaver.
/// The overlay must never be shown while unavailable; it would render black on the lock screen
/// and there is no way to dismiss it there.
final class SystemStateMonitor {
    private(set) var isScreenLocked: Bool
    private(set) var isSystemAsleep = false
    private(set) var areScreensAsleep = false
    private(set) var isScreensaverRunning = false

    var canShowOverlay: Bool {
        !isScreenLocked && !isSystemAsleep && !areScreensAsleep && !isScreensaverRunning
    }

    /// Fired when the screen becomes usable again (unlock, wake, screensaver stopped).
    var onBecameAvailable: (() -> Void)?
    /// Fired the moment the screen stops being usable (lock, sleep, screensaver started).
    var onBecameUnavailable: (() -> Void)?

    private var tokens: [Any] = []

    init() {
        isScreenLocked = Self.queryScreenLocked()

        let dnc = DistributedNotificationCenter.default()
        observe(dnc, "com.apple.screenIsLocked") { $0.isScreenLocked = true; $0.changed() }
        observe(dnc, "com.apple.screenIsUnlocked") { $0.isScreenLocked = false; $0.changed() }
        observe(dnc, "com.apple.screensaver.didstart") { $0.isScreensaverRunning = true; $0.changed() }
        observe(dnc, "com.apple.screensaver.didstop") { $0.isScreensaverRunning = false; $0.changed() }

        let wnc = NSWorkspace.shared.notificationCenter
        observe(wnc, NSWorkspace.willSleepNotification.rawValue) { $0.isSystemAsleep = true; $0.changed() }
        observe(wnc, NSWorkspace.didWakeNotification.rawValue) {
            $0.isSystemAsleep = false
            // After wake the screen is normally locked; the lock notification may have fired before sleep.
            $0.isScreenLocked = Self.queryScreenLocked()
            $0.changed()
        }
        observe(wnc, NSWorkspace.screensDidSleepNotification.rawValue) { $0.areScreensAsleep = true; $0.changed() }
        observe(wnc, NSWorkspace.screensDidWakeNotification.rawValue) { $0.areScreensAsleep = false; $0.changed() }
    }

    private var lastAvailability: Bool?

    private func changed() {
        let now = canShowOverlay
        defer { lastAvailability = now }
        guard now != (lastAvailability ?? true) else { return }
        if now { onBecameAvailable?() } else { onBecameUnavailable?() }
    }

    private func observe(_ center: NotificationCenter, _ name: String, _ handler: @escaping (SystemStateMonitor) -> Void) {
        let token = center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            handler(self)
        }
        tokens.append(token)
    }

    /// Current lock state from the window server session (works at launch, before any notification).
    static func queryScreenLocked() -> Bool {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        if let n = dict["CGSSessionScreenIsLocked"] as? NSNumber { return n.boolValue }
        return false
    }
}
