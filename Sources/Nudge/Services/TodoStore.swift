import Foundation
import Combine

final class TodoStore: ObservableObject {
    @Published private(set) var todos: [Todo] = [] {
        didSet { scheduleSave() }
    }

    private let fileURL: URL
    private var saveWorkItem: DispatchWorkItem?

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("Nudge", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("todos.json")
        load()
    }

    // MARK: Derived lists

    var pending: [Todo] {
        todos.filter { !$0.isDone }.sorted { a, b in
            switch (a.reminderAt, b.reminderAt) {
            case let (x?, y?): return x != y ? x < y : a.createdAt < b.createdAt
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.createdAt < b.createdAt
            }
        }
    }

    var completed: [Todo] {
        todos.filter { $0.isDone }.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    /// Pending todos bucketed by DayGroup, in display order, empty groups omitted.
    func groupedPending(now: Date = Date()) -> [(group: DayGroup, todos: [Todo])] {
        var buckets: [DayGroup: [Todo]] = [:]
        for todo in pending {
            buckets[DayGroup.classify(todo.reminderAt, now: now), default: []].append(todo)
        }
        return DayGroup.allCases.compactMap { g in
            guard let items = buckets[g], !items.isEmpty else { return nil }
            return (g, items)
        }
    }

    func todo(_ id: UUID) -> Todo? {
        todos.first { $0.id == id }
    }

    // MARK: Mutations

    func add(title: String, notes: String = "", reminderAt: Date?, repeatRule: RepeatRule = .none) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        todos.append(Todo(title: trimmed, notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                          reminderAt: reminderAt, repeatRule: repeatRule))
    }

    /// Replace a todo wholesale (used by the editor). Keeps `lastFiredAt` sane if the reminder moved.
    func replace(_ edited: Todo) {
        update(edited.id) { todo in
            let reminderChanged = todo.reminderAt != edited.reminderAt
            todo.title = edited.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? todo.title : edited.title.trimmingCharacters(in: .whitespacesAndNewlines)
            todo.notes = edited.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            todo.reminderAt = edited.reminderAt
            todo.repeatRule = edited.reminderAt == nil ? .none : edited.repeatRule
            if reminderChanged { todo.lastFiredAt = nil }
        }
    }

    /// Check off a todo. Repeating todos roll forward to their next occurrence instead of completing.
    func complete(_ id: UUID) {
        update(id) { todo in
            if todo.repeats, let current = todo.reminderAt,
               let next = todo.repeatRule.nextOccurrence(from: current) {
                todo.reminderAt = next
                todo.lastFiredAt = nil
                todo.isDone = false
            } else {
                todo.isDone = true
                todo.completedAt = Date()
            }
        }
    }

    func toggleDone(_ id: UUID) {
        guard let todo = todo(id) else { return }
        if todo.isDone {
            update(id) { t in
                t.isDone = false
                t.completedAt = nil
            }
        } else {
            complete(id)
        }
    }

    func rename(_ id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        update(id) { $0.title = trimmed }
    }

    func setReminder(_ id: UUID, to date: Date?) {
        update(id) { todo in
            todo.reminderAt = date
            todo.lastFiredAt = nil
            if date == nil { todo.repeatRule = .none }
        }
    }

    func setRepeat(_ id: UUID, to rule: RepeatRule) {
        update(id) { $0.repeatRule = $0.reminderAt == nil ? .none : rule }
    }

    func snooze(_ id: UUID, by interval: TimeInterval) {
        update(id) { todo in
            todo.reminderAt = Date().addingTimeInterval(interval)
            todo.lastFiredAt = nil
        }
    }

    func markFired(_ id: UUID) {
        update(id) { $0.lastFiredAt = Date() }
    }

    /// Forget that a reminder was shown so it fires again on the next tick
    /// (used when the overlay is torn down by a screen lock or sleep).
    func resetFired(_ id: UUID) {
        update(id) { $0.lastFiredAt = nil }
    }

    func delete(_ id: UUID) {
        todos.removeAll { $0.id == id }
    }

    func clearCompleted() {
        todos.removeAll { $0.isDone }
    }

    /// All todos whose reminder time has passed and haven't been shown yet, earliest first.
    func dueToFire() -> [Todo] {
        todos.filter { $0.isDueToFire }
            .sorted { ($0.reminderAt ?? .distantPast) < ($1.reminderAt ?? .distantPast) }
    }

    /// The next todo whose reminder time has passed and hasn't been shown yet.
    func nextDueToFire() -> Todo? {
        dueToFire().first
    }

    private func update(_ id: UUID, _ change: (inout Todo) -> Void) {
        guard let idx = todos.firstIndex(where: { $0.id == id }) else { return }
        var copy = todos[idx]
        change(&copy)
        todos[idx] = copy
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([Todo].self, from: data) {
            todos = decoded
        }
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.save() }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(todos) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
