import Foundation
import Combine
import Carbon.HIToolbox

/// Preset global shortcuts for the Quick Add panel (Carbon key codes / modifiers).
enum HotkeyOption: String, CaseIterable, Identifiable {
    case optCmdN, ctrlOptSpace, cmdShiftSpace, ctrlShiftN, optSpace, ctrlOptN, cmdShiftT

    var id: String { rawValue }

    var label: String {
        switch self {
        case .optCmdN: return "⌥ ⌘ N"
        case .ctrlOptSpace: return "⌃ ⌥ Space"
        case .cmdShiftSpace: return "⇧ ⌘ Space"
        case .ctrlShiftN: return "⌃ ⇧ N"
        case .optSpace: return "⌥ Space"
        case .ctrlOptN: return "⌃ ⌥ N"
        case .cmdShiftT: return "⇧ ⌘ T"
        }
    }

    var keyCode: UInt32 {
        switch self {
        case .optCmdN, .ctrlShiftN, .ctrlOptN: return UInt32(kVK_ANSI_N)
        case .ctrlOptSpace, .cmdShiftSpace, .optSpace: return UInt32(kVK_Space)
        case .cmdShiftT: return UInt32(kVK_ANSI_T)
        }
    }

    var modifiers: UInt32 {
        switch self {
        case .optCmdN: return UInt32(optionKey | cmdKey)
        case .ctrlOptSpace: return UInt32(controlKey | optionKey)
        case .cmdShiftSpace: return UInt32(cmdKey | shiftKey)
        case .ctrlShiftN: return UInt32(controlKey | shiftKey)
        case .optSpace: return UInt32(optionKey)
        case .ctrlOptN: return UInt32(controlKey | optionKey)
        case .cmdShiftT: return UInt32(cmdKey | shiftKey)
        }
    }
}

/// How a due reminder is surfaced.
enum ReminderStyle: String, CaseIterable, Identifiable {
    case overlay, notification, both

    var id: String { rawValue }

    var label: String {
        switch self {
        case .overlay: return "Screen takeover"
        case .notification: return "Notification banner"
        case .both: return "Both"
        }
    }

    var usesOverlay: Bool { self != .notification }
    var usesNotification: Bool { self != .overlay }
}

/// User preferences, persisted to UserDefaults. Shared by views and services.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let d = UserDefaults.standard

    // General
    @Published var groupByDate: Bool { didSet { d.set(groupByDate, forKey: "groupByDate") } }
    @Published var showDockIcon: Bool { didSet { d.set(showDockIcon, forKey: "showDockIcon") } }
    @Published var showCompletedSection: Bool { didSet { d.set(showCompletedSection, forKey: "showCompletedSection") } }
    @Published var morningHour: Int { didSet { d.set(morningHour, forKey: "morningHour") } }
    @Published var eveningHour: Int { didSet { d.set(eveningHour, forKey: "eveningHour") } }

    // Reminders / overlay
    @Published var reminderStyle: ReminderStyle { didSet { d.set(reminderStyle.rawValue, forKey: "reminderStyle") } }
    @Published var coverAllScreens: Bool { didSet { d.set(coverAllScreens, forKey: "coverAllScreens") } }
    @Published var chimeSound: String { didSet { d.set(chimeSound, forKey: "chimeSound") } }
    @Published var chimeRepeatSeconds: Int { didSet { d.set(chimeRepeatSeconds, forKey: "chimeRepeatSeconds") } }
    @Published var snoozeMinutes: [Int] { didSet { d.set(snoozeMinutes, forKey: "snoozeMinutes") } }

    // Quick Add
    @Published var hotkeyEnabled: Bool { didSet { d.set(hotkeyEnabled, forKey: "hotkeyEnabled") } }
    @Published var hotkey: HotkeyOption { didSet { d.set(hotkey.rawValue, forKey: "hotkey") } }

    static let snoozeChoices = [1, 2, 3, 5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 240]
    static let chimeRepeatChoices = [0, 10, 15, 30, 60, 120]

    /// Names of the built-in system alert sounds ("Glass", "Ping", …).
    static let availableSounds: [String] = {
        let dir = URL(fileURLWithPath: "/System/Library/Sounds")
        let names = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "aiff" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted() ?? []
        return names.isEmpty ? ["Glass"] : names
    }()

    private init() {
        d.register(defaults: [
            "groupByDate": true,
            "showDockIcon": true,
            "showCompletedSection": true,
            "morningHour": 9,
            "eveningHour": 18,
            "reminderStyle": ReminderStyle.both.rawValue,
            "coverAllScreens": true,
            "chimeSound": "Glass",
            "chimeRepeatSeconds": 30,
            "snoozeMinutes": [5, 15, 60],
            "hotkeyEnabled": true,
            "hotkey": HotkeyOption.optCmdN.rawValue,
        ])
        groupByDate = d.bool(forKey: "groupByDate")
        showDockIcon = d.bool(forKey: "showDockIcon")
        showCompletedSection = d.bool(forKey: "showCompletedSection")
        morningHour = d.integer(forKey: "morningHour")
        eveningHour = d.integer(forKey: "eveningHour")
        reminderStyle = ReminderStyle(rawValue: d.string(forKey: "reminderStyle") ?? "") ?? .both
        coverAllScreens = d.bool(forKey: "coverAllScreens")
        chimeSound = d.string(forKey: "chimeSound") ?? "Glass"
        chimeRepeatSeconds = d.integer(forKey: "chimeRepeatSeconds")
        let mins = d.array(forKey: "snoozeMinutes") as? [Int] ?? [5, 15, 60]
        snoozeMinutes = mins.count == 3 ? mins : [5, 15, 60]
        hotkeyEnabled = d.bool(forKey: "hotkeyEnabled")
        hotkey = HotkeyOption(rawValue: d.string(forKey: "hotkey") ?? "") ?? .optCmdN
    }
}

extension Int {
    /// "5 min", "1 hour", "1.5 hours", "2 hours"
    var minutesLabel: String {
        if self < 60 { return "\(self) min" }
        let h = Double(self) / 60
        let text = h == h.rounded() ? String(Int(h)) : String(format: "%.1f", h)
        return "\(text) \(h == 1 ? "hour" : "hours")"
    }
}
