import Foundation
import Combine

/// Pull-merge-push sync of the todo store with a Supabase project.
@MainActor
final class SyncService: ObservableObject {
    enum Status: Equatable {
        case notConfigured, signedOut, idle, syncing, error(String)
    }

    @Published private(set) var status: Status = .notConfigured
    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var accountEmail: String?

    private let store: TodoStore
    private let settings = AppSettings.shared
    private var client: SupabaseClient?
    private var cancellables = Set<AnyCancellable>()
    private var pushDebounce: DispatchWorkItem?
    private var periodic: Timer?
    private var inFlight = false
    private var lastPullCursor: Date? {
        get { UserDefaults.standard.object(forKey: "sync.lastPullCursor") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "sync.lastPullCursor") }
    }

    init(store: TodoStore) {
        self.store = store
        rebuildClient()

        Publishers.CombineLatest(settings.$supabaseURL, settings.$supabaseAnonKey)
            .dropFirst()
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { [weak self] _, _ in self?.rebuildClient() }
            .store(in: &cancellables)

        // Push shortly after any local change.
        store.$todos
            .dropFirst()
            .sink { [weak self] todos in
                guard let self, self.client?.isSignedIn == true, todos.contains(where: { $0.dirty }) else { return }
                self.scheduleSyncSoon()
            }
            .store(in: &cancellables)

        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.syncNow() }
        }
        RunLoop.main.add(t, forMode: .common)
        periodic = t

        Task { await syncNow() }
    }

    var isSignedIn: Bool { client?.isSignedIn == true }
    var isConfigured: Bool { client != nil }

    private func rebuildClient() {
        client = SupabaseClient(urlString: settings.supabaseURL, anonKey: settings.supabaseAnonKey)
        if let c = client {
            accountEmail = c.session?.email
            status = c.isSignedIn ? .idle : .signedOut
        } else {
            accountEmail = nil
            status = .notConfigured
        }
    }

    // MARK: Account

    func signIn(email: String, password: String) async -> String? {
        guard let client else { return "Enter your Supabase URL and anon key first." }
        do {
            let s = try await client.signIn(email: email, password: password)
            accountEmail = s.email
            status = .idle
            lastPullCursor = nil
            markAllDirtyForFirstPush()
            await syncNow()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Returns nil on success, a message otherwise. "confirm" means the account was created but
    /// needs email confirmation before signing in.
    func signUp(email: String, password: String) async -> String? {
        guard let client else { return "Enter your Supabase URL and anon key first." }
        do {
            if let s = try await client.signUp(email: email, password: password) {
                accountEmail = s.email
                status = .idle
                lastPullCursor = nil
                markAllDirtyForFirstPush()
                await syncNow()
                return nil
            }
            return "Account created. Check your email for a confirmation link, then sign in."
        } catch {
            return error.localizedDescription
        }
    }

    func signOut() {
        client?.signOut()
        accountEmail = nil
        lastPullCursor = nil
        status = client == nil ? .notConfigured : .signedOut
    }

    /// Local todos that predate the account (or came from another account) should all be offered.
    private func markAllDirtyForFirstPush() {
        store.markAllDirty()
    }

    // MARK: Sync

    func scheduleSyncSoon() {
        pushDebounce?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in await self?.syncNow() }
        }
        pushDebounce = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: item)
    }

    func syncNow() async {
        guard let client, client.isSignedIn, !inFlight else { return }
        inFlight = true
        status = .syncing
        defer { inFlight = false }

        do {
            // 1. Pull everything changed since the last cursor and merge (newer wins).
            var query: [String: String] = ["order": "updated_at.asc"]
            if let cursor = lastPullCursor {
                query["updated_at"] = "gt.\(PostgresDate.string(cursor))"
            }
            let data = try await client.select(table: "todos", query: query)
            let rows = (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
            let remotes = rows.compactMap(Self.todo(fromRow:))
            store.applyRemote(remotes)
            if let newest = remotes.map(\.updatedAt).max() {
                lastPullCursor = newest
            }

            // 2. Push local changes.
            let dirty = store.dirtyTodos
            if !dirty.isEmpty {
                try await client.upsert(table: "todos", rows: dirty.map(Self.row(from:)))
                store.markPushed(dirty)
                // Our own writes are now the newest rows; move the cursor past them so the next
                // pull doesn't echo them back.
                if let newest = dirty.map(\.updatedAt).max(), newest > (lastPullCursor ?? .distantPast) {
                    lastPullCursor = newest
                }
            }

            store.purgeTombstones()
            lastSyncAt = Date()
            status = .idle
        } catch {
            status = .error(error.localizedDescription)
            if let e = error as? SupabaseError, e.status == 401 {
                // Session is dead; make the user sign in again.
                client.signOut()
                accountEmail = nil
                status = .signedOut
            }
        }
    }

    // MARK: Row mapping

    private static func row(from t: Todo) -> [String: Any] {
        var r: [String: Any] = [
            "id": t.id.uuidString.lowercased(),
            "title": t.title,
            "notes": t.notes,
            "is_done": t.isDone,
            "created_at": PostgresDate.string(t.createdAt),
            "repeat_rule": t.repeatRule.rawValue,
            "updated_at": PostgresDate.string(t.updatedAt),
        ]
        r["completed_at"] = t.completedAt.map(PostgresDate.string) ?? NSNull()
        r["reminder_at"] = t.reminderAt.map(PostgresDate.string) ?? NSNull()
        r["deleted_at"] = t.deletedAt.map(PostgresDate.string) ?? NSNull()
        return r
    }

    private static func todo(fromRow r: [String: Any]) -> Todo? {
        guard let idString = r["id"] as? String, let id = UUID(uuidString: idString),
              let title = r["title"] as? String else { return nil }
        var t = Todo(title: title)
        t.id = id
        t.notes = r["notes"] as? String ?? ""
        t.isDone = r["is_done"] as? Bool ?? false
        t.createdAt = PostgresDate.parse(r["created_at"] as? String) ?? Date()
        t.completedAt = PostgresDate.parse(r["completed_at"] as? String)
        t.reminderAt = PostgresDate.parse(r["reminder_at"] as? String)
        t.repeatRule = RepeatRule(rawValue: r["repeat_rule"] as? String ?? "") ?? .none
        t.updatedAt = PostgresDate.parse(r["updated_at"] as? String) ?? t.createdAt
        t.deletedAt = PostgresDate.parse(r["deleted_at"] as? String)
        t.dirty = false
        return t
    }
}
