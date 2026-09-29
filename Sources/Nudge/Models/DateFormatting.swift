import Foundation

extension Date {
    /// "Today 3:45 PM", "Tomorrow 9:00 AM", "Mon, Oct 5 · 3:00 PM"
    var reminderDescription: String {
        let cal = Calendar.current
        let time = Self.timeFormatter.string(from: self)
        if cal.isDateInToday(self) { return "Today \(time)" }
        if cal.isDateInTomorrow(self) { return "Tomorrow \(time)" }
        if cal.isDateInYesterday(self) { return "Yesterday \(time)" }
        return "\(Self.dayFormatter.string(from: self)) · \(time)"
    }

    var timeOnly: String { Self.timeFormatter.string(from: self) }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE MMM d")
        return f
    }()

    /// "9:00 AM" for a bare hour, in the user's locale.
    static func hourLabel(_ hour: Int) -> String {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = hour
        comps.minute = 0
        return timeFormatter.string(from: Calendar.current.date(from: comps) ?? Date())
    }

    /// Next occurrence of the given hour today or tomorrow.
    static func nextOccurrence(hour: Int, minute: Int = 0) -> Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: Date())
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        let today = cal.date(from: comps)!
        return today > Date() ? today : cal.date(byAdding: .day, value: 1, to: today)!
    }

    static func tomorrow(hour: Int, minute: Int = 0) -> Date {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: Date())!
        var comps = cal.dateComponents([.year, .month, .day], from: tomorrow)
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        return cal.date(from: comps)!
    }

    /// Rounded up to the next 5-minute boundary; a sensible default for a custom picker.
    static func roundedUpToNextFiveMinutes() -> Date {
        let cal = Calendar.current
        let now = Date()
        let minute = cal.component(.minute, from: now)
        let add = 5 - (minute % 5)
        let d = cal.date(byAdding: .minute, value: add, to: now)!
        return cal.date(bySetting: .second, value: 0, of: d) ?? d
    }
}
