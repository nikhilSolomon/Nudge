import Foundation

enum RepeatRule: String, Codable, CaseIterable, Identifiable {
    case none, daily, weekdays, weekly, biweekly, monthly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "Never"
        case .daily: return "Every day"
        case .weekdays: return "Weekdays"
        case .weekly: return "Every week"
        case .biweekly: return "Every 2 weeks"
        case .monthly: return "Every month"
        }
    }

    var shortLabel: String {
        switch self {
        case .none: return ""
        case .daily: return "Daily"
        case .weekdays: return "Weekdays"
        case .weekly: return "Weekly"
        case .biweekly: return "Every 2 wks"
        case .monthly: return "Monthly"
        }
    }

    /// One period after `date`, keeping the time of day.
    func next(after date: Date) -> Date? {
        let cal = Calendar.current
        switch self {
        case .none:
            return nil
        case .daily:
            return cal.date(byAdding: .day, value: 1, to: date)
        case .weekdays:
            var d = date
            repeat {
                d = cal.date(byAdding: .day, value: 1, to: d)!
            } while cal.isDateInWeekend(d)
            return d
        case .weekly:
            return cal.date(byAdding: .weekOfYear, value: 1, to: date)
        case .biweekly:
            return cal.date(byAdding: .weekOfYear, value: 2, to: date)
        case .monthly:
            return cal.date(byAdding: .month, value: 1, to: date)
        }
    }

    /// First occurrence strictly after `now`, stepping from `date`.
    func nextOccurrence(from date: Date, after now: Date = Date()) -> Date? {
        guard self != .none else { return nil }
        var d = date
        var guardCount = 0
        repeat {
            guard let n = next(after: d) else { return nil }
            d = n
            guardCount += 1
        } while d <= now && guardCount < 5000
        return d
    }
}

struct Todo: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var notes: String
    var isDone: Bool
    var createdAt: Date
    var completedAt: Date?
    /// When the reminder should grab the screen. nil = no reminder.
    var reminderAt: Date?
    /// Set when the overlay has been shown for the current `reminderAt`.
    /// Snoozing moves `reminderAt` forward and clears this so it fires again.
    var lastFiredAt: Date?
    var repeatRule: RepeatRule

    init(title: String, notes: String = "", reminderAt: Date? = nil, repeatRule: RepeatRule = .none) {
        self.id = UUID()
        self.title = title
        self.notes = notes
        self.isDone = false
        self.createdAt = Date()
        self.reminderAt = reminderAt
        self.repeatRule = reminderAt == nil ? .none : repeatRule
    }

    var hasReminder: Bool { reminderAt != nil }
    var repeats: Bool { repeatRule != .none && reminderAt != nil }

    var isOverdue: Bool {
        guard let r = reminderAt, !isDone else { return false }
        return r <= Date()
    }

    /// True when the reminder time has passed and the overlay hasn't been shown for it yet.
    var isDueToFire: Bool {
        guard !isDone, let r = reminderAt, r <= Date() else { return false }
        if let fired = lastFiredAt { return fired < r }
        return true
    }

    // Tolerant decoding so older todos.json files (without notes/repeat) still load.
    enum CodingKeys: String, CodingKey {
        case id, title, notes, isDone, createdAt, completedAt, reminderAt, lastFiredAt, repeatRule
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decode(String.self, forKey: .title)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        isDone = try c.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        reminderAt = try c.decodeIfPresent(Date.self, forKey: .reminderAt)
        lastFiredAt = try c.decodeIfPresent(Date.self, forKey: .lastFiredAt)
        repeatRule = try c.decodeIfPresent(RepeatRule.self, forKey: .repeatRule) ?? .none
    }
}

/// Buckets used to group pending todos by how far out they are.
enum DayGroup: Int, CaseIterable, Identifiable {
    case overdue, today, tomorrow, thisWeek, later, noDate

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .overdue: return "Overdue"
        case .today: return "Today"
        case .tomorrow: return "Tomorrow"
        case .thisWeek: return "Next 7 days"
        case .later: return "Later"
        case .noDate: return "No date"
        }
    }

    var symbol: String {
        switch self {
        case .overdue: return "exclamationmark.circle.fill"
        case .today: return "sun.max.fill"
        case .tomorrow: return "sunrise.fill"
        case .thisWeek: return "calendar"
        case .later: return "calendar.badge.clock"
        case .noDate: return "tray"
        }
    }

    static func classify(_ date: Date?, now: Date = Date()) -> DayGroup {
        guard let date else { return .noDate }
        let cal = Calendar.current
        if date <= now { return .overdue }
        if cal.isDateInToday(date) { return .today }
        if cal.isDateInTomorrow(date) { return .tomorrow }
        let startOfToday = cal.startOfDay(for: now)
        if let weekOut = cal.date(byAdding: .day, value: 7, to: startOfToday), date < weekOut {
            return .thisWeek
        }
        return .later
    }
}
