package dev.nudge.android.data

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.io.File

/** In-memory list persisted as a JSON file. Small data, simple and crash-safe (atomic rename). */
class TodoRepository(context: Context) {
    private val file = File(context.filesDir, "todos.json")
    private val tmp = File(context.filesDir, "todos.json.tmp")
    private val lock = Any()

    private val _todos = MutableStateFlow(load())
    val todos: StateFlow<List<Todo>> = _todos

    /** Invoked after every user-visible change (reschedule alarms, kick sync). */
    var onChanged: (() -> Unit)? = null

    // MARK: derived

    val live: List<Todo> get() = _todos.value.filter { !it.isDeleted }

    fun pending(): List<Todo> = live.filter { !it.isDone }.sortedWith(compareBy<Todo>(
        { it.reminderAt == null }, { it.reminderAt ?: Long.MAX_VALUE }, { it.createdAt }))

    fun completed(): List<Todo> = live.filter { it.isDone }.sortedByDescending { it.completedAt ?: 0L }

    fun grouped(now: Long = System.currentTimeMillis()): List<Pair<DayGroup, List<Todo>>> {
        val buckets = pending().groupBy { DayGroup.classify(it.reminderAt, now) }
        return DayGroup.entries.mapNotNull { g -> buckets[g]?.let { g to it } }
    }

    fun get(id: String): Todo? = _todos.value.firstOrNull { it.id == id && !it.isDeleted }

    fun dueToFire(now: Long = System.currentTimeMillis()): List<Todo> =
        _todos.value.filter { it.isDueToFire(now) }.sortedBy { it.reminderAt }

    /** When the alarm should next ring: the earliest unfired reminder (possibly already past). */
    fun nextAlarmTime(now: Long = System.currentTimeMillis()): Long? =
        _todos.value.filter { !it.isDone && !it.isDeleted && it.reminderAt != null &&
                (it.lastFiredAt == null || it.lastFiredAt < it.reminderAt) }
            .minOfOrNull { it.reminderAt!! }

    // MARK: mutations

    fun add(title: String, notes: String = "", reminderAt: Long? = null, repeat: RepeatRule = RepeatRule.NONE) {
        val t = title.trim()
        if (t.isEmpty()) return
        commit(_todos.value + Todo(title = t, notes = notes.trim(), reminderAt = reminderAt,
            repeatRule = if (reminderAt == null) RepeatRule.NONE else repeat))
    }

    fun replace(edited: Todo) = update(edited.id) { old ->
        val title = edited.title.trim().ifEmpty { old.title }
        val reminderChanged = old.reminderAt != edited.reminderAt
        old.copy(
            title = title,
            notes = edited.notes.trim(),
            reminderAt = edited.reminderAt,
            repeatRule = if (edited.reminderAt == null) RepeatRule.NONE else edited.repeatRule,
            lastFiredAt = if (reminderChanged) null else old.lastFiredAt,
        )
    }

    /** Check off. Repeating todos roll forward to the next occurrence instead of completing. */
    fun complete(id: String) = update(id) { t ->
        val next = if (t.repeats) t.repeatRule.nextOccurrence(t.reminderAt!!) else null
        if (next != null) t.copy(reminderAt = next, lastFiredAt = null, isDone = false)
        else t.copy(isDone = true, completedAt = System.currentTimeMillis())
    }

    fun toggleDone(id: String) {
        val t = get(id) ?: return
        if (t.isDone) update(id) { it.copy(isDone = false, completedAt = null) } else complete(id)
    }

    fun setReminder(id: String, at: Long?) = update(id) {
        it.copy(reminderAt = at, lastFiredAt = null, repeatRule = if (at == null) RepeatRule.NONE else it.repeatRule)
    }

    fun setRepeat(id: String, rule: RepeatRule) = update(id) {
        it.copy(repeatRule = if (it.reminderAt == null) RepeatRule.NONE else rule)
    }

    fun snooze(id: String, millis: Long) = update(id) {
        it.copy(reminderAt = System.currentTimeMillis() + millis, lastFiredAt = null)
    }

    fun markFired(id: String) = update(id, touch = false) { it.copy(lastFiredAt = System.currentTimeMillis()) }
    fun resetFired(id: String) = update(id, touch = false) { it.copy(lastFiredAt = null) }

    fun delete(id: String) = update(id) { it.copy(deletedAt = System.currentTimeMillis()) }

    fun clearCompleted() {
        val now = System.currentTimeMillis()
        commit(_todos.value.map { if (it.isDone && !it.isDeleted) it.copy(deletedAt = now, updatedAt = now, dirty = true) else it })
    }

    private fun update(id: String, touch: Boolean = true, change: (Todo) -> Todo) {
        val list = _todos.value
        val idx = list.indexOfFirst { it.id == id }
        if (idx < 0) return
        var t = change(list[idx])
        if (touch) t = t.copy(updatedAt = System.currentTimeMillis(), dirty = true)
        commit(list.toMutableList().also { it[idx] = t }, notify = touch)
    }

    // MARK: sync support

    fun dirtyTodos(): List<Todo> = _todos.value.filter { it.dirty }

    fun markAllDirty() = commit(_todos.value.map { it.copy(dirty = true) }, notify = false)

    /** Merge rows from the server; newer updatedAt wins. Keeps local fired state unless the time moved. */
    fun applyRemote(remotes: List<Todo>) {
        if (remotes.isEmpty()) return
        val list = _todos.value.toMutableList()
        val index = list.withIndex().associate { it.value.id to it.index }.toMutableMap()
        var changed = false
        for (r0 in remotes) {
            val r = r0.copy(dirty = false)
            val i = index[r.id]
            if (i != null) {
                val local = list[i]
                if (r.updatedAt <= local.updatedAt) continue
                list[i] = r.copy(lastFiredAt = if (r.reminderAt == local.reminderAt) local.lastFiredAt else null)
                changed = true
            } else if (!r.isDeleted) {
                index[r.id] = list.size
                list.add(r.copy(lastFiredAt = null))
                changed = true
            }
        }
        if (changed) commit(list, notify = true, fromSync = true)
    }

    fun markPushed(pushed: List<Todo>) {
        val snapshot = pushed.associate { it.id to it.updatedAt }
        commit(_todos.value.map { t -> if (snapshot[t.id] == t.updatedAt) t.copy(dirty = false) else t }, notify = false)
    }

    fun purgeTombstones(days: Int = 60) {
        val cutoff = System.currentTimeMillis() - days * 86_400_000L
        val kept = _todos.value.filter { !(it.deletedAt != null && !it.dirty && it.deletedAt < cutoff) }
        if (kept.size != _todos.value.size) commit(kept, notify = false)
    }

    /** Set by [dev.nudge.android.sync.SyncManager] so remote-driven changes don't trigger a push loop. */
    var onRemoteApplied: (() -> Unit)? = null

    // MARK: persistence

    private fun commit(list: List<Todo>, notify: Boolean = true, fromSync: Boolean = false) {
        _todos.value = list
        save(list)
        if (notify) {
            if (fromSync) onRemoteApplied?.invoke() else onChanged?.invoke()
        }
    }

    private fun load(): List<Todo> = try {
        if (file.exists()) Todo.listFromJson(file.readText()) else emptyList()
    } catch (_: Exception) {
        emptyList()
    }

    private fun save(list: List<Todo>) {
        synchronized(lock) {
            try {
                tmp.writeText(Todo.listToJson(list))
                if (!tmp.renameTo(file)) {
                    file.writeText(Todo.listToJson(list))
                }
            } catch (_: Exception) {
            }
        }
    }
}
