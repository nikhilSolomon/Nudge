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

    /// Everything that isn't a delete tombstone.
    var live: [Todo] { todos.filter { !$0.isDeleted } }

    var pending: [Todo] {
        live.filter { !$0.isDone }.sorted { a, b in
            switch (a.reminderAt, b.reminderAt) {
            case let (x?, y?): return x != y ? x < y : a.createdAt < b.createdAt
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.createdAt < b.createdAt
            }
        }
    }

    var completed: [Todo] {
        live.filter { $0.isDone }.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
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
        todos.first { $0.id == id && !$0.isDeleted }
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
        update(id, touch: false) { $0.lastFiredAt = Date() }
    }

    /// Forget that a reminder was shown so it fires again on the next tick
    /// (used when the overlay is torn down by a screen lock or sleep).
    func resetFired(_ id: UUID) {
        update(id, touch: false) { $0.lastFiredAt = nil }
    }

    /// Soft delete: keeps a tombstone so the deletion syncs to other devices.
    func delete(_ id: UUID) {
        update(id) { $0.deletedAt = Date() }
    }

    func clearCompleted() {
        let now = Date()
        todos = todos.map { t in
            guard t.isDone, !t.isDeleted else { return t }
            var c = t
            c.deletedAt = now
            c.updatedAt = now
            c.dirty = true
            return c
        }
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

    /// `touch` = this is a user-visible change that should sync (bumps updatedAt, marks dirty).
    private func update(_ id: UUID, touch: Bool = true, _ change: (inout Todo) -> Void) {
        guard let idx = todos.firstIndex(where: { $0.id == id }) else { return }
        var copy = todos[idx]
        change(&copy)
        if touch {
            copy.updatedAt = Date()
            copy.dirty = true
        }
        todos[idx] = copy
    }

    // MARK: Sync support

    var dirtyTodos: [Todo] { todos.filter { $0.dirty } }

    /// On first sign-in: offer every local todo to the server.
    func markAllDirty() {
        todos = todos.map { var c = $0; c.dirty = true; return c }
    }

    /// Merge rows pulled from the server. Newer `updatedAt` wins; local reminder "already fired"
    /// state is kept unless the reminder time itself changed.
    func applyRemote(_ remotes: [Todo]) {
        guard !remotes.isEmpty else { return }
        var list = todos
        var index: [UUID: Int] = [:]
        for (i, t) in list.enumerated() { index[t.id] = i }

        for var remote in remotes {
            remote.dirty = false
            if let i = index[remote.id] {
                let local = list[i]
                guard remote.updatedAt > local.updatedAt else { continue }
                remote.lastFiredAt = (remote.reminderAt == local.reminderAt) ? local.lastFiredAt : nil
                list[i] = remote
            } else if !remote.isDeleted {
                remote.lastFiredAt = nil
                index[remote.id] = list.count
                list.append(remote)
            }
        }
        todos = list
    }

    /// After a successful push: clear dirty on rows that haven't changed since the snapshot was taken.
    func markPushed(_ pushed: [Todo]) {
        let snapshot = Dictionary(uniqueKeysWithValues: pushed.map { ($0.id, $0.updatedAt) })
        todos = todos.map { t in
            guard let at = snapshot[t.id], at == t.updatedAt else { return t }
            var c = t
            c.dirty = false
            return c
        }
    }

    /// Drop everything local that came from the server (on sign-out keep local copies, so this is
    /// only used when switching accounts).
    func purgeTombstones(olderThan days: Int = 60) {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        todos.removeAll { t in
            guard let d = t.deletedAt, !t.dirty else { return false }
            return d < cutoff
        }
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
