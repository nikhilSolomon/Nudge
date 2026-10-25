package dev.nudge.android.sync

import android.content.Context
import dev.nudge.android.data.Dates
import dev.nudge.android.data.RepeatRule
import dev.nudge.android.data.Settings
import dev.nudge.android.data.Todo
import dev.nudge.android.data.TodoRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

enum class SyncStatus { NOT_CONFIGURED, SIGNED_OUT, IDLE, SYNCING, ERROR }

data class SyncState(
    val status: SyncStatus = SyncStatus.NOT_CONFIGURED,
    val error: String? = null,
    val lastSyncAt: Long? = null,
    val email: String? = null,
)

/** Pull-merge-push against Supabase. Mirrors the Mac implementation. */
class SyncManager(private val context: Context, private val repo: TodoRepository, private val settings: Settings) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val prefs = context.getSharedPreferences("sync", Context.MODE_PRIVATE)
    private val mutex = Mutex()
    private var debounce: Job? = null

    private val _state = MutableStateFlow(SyncState())
    val state: StateFlow<SyncState> = _state

    @Volatile private var client: SupabaseClient? = null

    init {
        rebuildClient()
        scope.launch {
            settings.state.collect { rebuildClient() }
        }
        repo.onRemoteApplied = { /* local alarms are rescheduled by Graph via onChanged only for user edits */ }
    }

    val isConfigured get() = client != null
    val isSignedIn get() = client?.isSignedIn == true

    private fun rebuildClient() {
        val s = settings.value
        val url = s.supabaseUrl.trim()
        val ok = url.startsWith("http") && s.supabaseAnonKey.isNotBlank()
        val sameConfig = client != null && lastUrl == url && lastKey == s.supabaseAnonKey
        if (sameConfig) return
        lastUrl = url; lastKey = s.supabaseAnonKey
        client = if (ok) SupabaseClient(context, url, s.supabaseAnonKey) else null
        _state.value = _state.value.copy(
            status = when {
                client == null -> SyncStatus.NOT_CONFIGURED
                client?.isSignedIn == true -> SyncStatus.IDLE
                else -> SyncStatus.SIGNED_OUT
            },
            email = client?.session?.email,
        )
    }
    private var lastUrl = ""
    private var lastKey = ""

    // MARK: account

    suspend fun signIn(email: String, password: String): String? = withContext(Dispatchers.IO) {
        val c = client ?: return@withContext "Enter your Supabase URL and anon key first."
        try {
            val s = c.signIn(email, password)
            afterAuth(s.email)
            null
        } catch (e: Exception) { e.message ?: "Sign-in failed" }
    }

    suspend fun signUp(email: String, password: String): String? = withContext(Dispatchers.IO) {
        val c = client ?: return@withContext "Enter your Supabase URL and anon key first."
        try {
            val s = c.signUp(email, password)
            if (s == null) "Account created. Check your email for a confirmation link, then sign in."
            else { afterAuth(s.email); null }
        } catch (e: Exception) { e.message ?: "Sign-up failed" }
    }

    private suspend fun afterAuth(email: String) {
        prefs.edit().remove("cursor").apply()
        repo.markAllDirty()
        _state.value = _state.value.copy(status = SyncStatus.IDLE, email = email, error = null)
        syncNow()
    }

    fun signOut() {
        scope.launch(Dispatchers.IO) { client?.signOut() }
        prefs.edit().remove("cursor").apply()
        _state.value = _state.value.copy(
            status = if (client == null) SyncStatus.NOT_CONFIGURED else SyncStatus.SIGNED_OUT, email = null, error = null)
    }

    // MARK: sync

    fun scheduleSoon() {
        if (!isSignedIn) return
        debounce?.cancel()
        debounce = scope.launch {
            delay(2000)
            syncNow()
        }
    }

    suspend fun syncNow() = withContext(Dispatchers.IO) {
        val c = client ?: return@withContext
        if (!c.isSignedIn) return@withContext
        if (!mutex.tryLock()) return@withContext
        try {
            _state.value = _state.value.copy(status = SyncStatus.SYNCING, error = null)

            // 1. pull
            val cursor = prefs.getLong("cursor", -1L).takeIf { it > 0 }
            val query = mutableMapOf("order" to "updated_at.asc")
            if (cursor != null) query["updated_at"] = "gt.${Dates.iso(cursor)}"
            val rows = c.select("todos", query)
            val remotes = (0 until rows.length()).mapNotNull { fromRow(rows.getJSONObject(it)) }
            repo.applyRemote(remotes)
            var newCursor = remotes.maxOfOrNull { it.updatedAt } ?: cursor

            // 2. push
            val dirty = repo.dirtyTodos()
            if (dirty.isNotEmpty()) {
                c.upsert("todos", JSONArray().apply { dirty.forEach { put(toRow(it)) } })
                repo.markPushed(dirty)
                val newest = dirty.maxOf { it.updatedAt }
                if (newCursor == null || newest > newCursor) newCursor = newest
            }
            if (newCursor != null) prefs.edit().putLong("cursor", newCursor).apply()

            repo.purgeTombstones()
            _state.value = _state.value.copy(status = SyncStatus.IDLE, lastSyncAt = System.currentTimeMillis(), error = null)
        } catch (e: Exception) {
            if (e is SupabaseException && e.status == 401) {
                c.signOut()
                _state.value = _state.value.copy(status = SyncStatus.SIGNED_OUT, email = null, error = "Session expired. Sign in again.")
            } else {
                _state.value = _state.value.copy(status = SyncStatus.ERROR, error = e.message ?: "Sync failed")
            }
        } finally {
            mutex.unlock()
        }
    }

    // MARK: rows

    private fun toRow(t: Todo): JSONObject = JSONObject().apply {
        put("id", t.id.lowercase())
        put("title", t.title)
        put("notes", t.notes)
        put("is_done", t.isDone)
        put("created_at", Dates.iso(t.createdAt))
        put("completed_at", t.completedAt?.let { Dates.iso(it) } ?: JSONObject.NULL)
        put("reminder_at", t.reminderAt?.let { Dates.iso(it) } ?: JSONObject.NULL)
        put("repeat_rule", t.repeatRule.key)
        put("updated_at", Dates.iso(t.updatedAt))
        put("deleted_at", t.deletedAt?.let { Dates.iso(it) } ?: JSONObject.NULL)
    }

    private fun fromRow(r: JSONObject): Todo? {
        val id = r.optString("id", "")
        val title = r.optString("title", "")
        if (id.isEmpty() || title.isEmpty()) return null
        val created = Dates.parseIso(r.optString("created_at", null)) ?: System.currentTimeMillis()
        return Todo(
            id = id,
            title = title,
            notes = r.optString("notes", ""),
            isDone = r.optBoolean("is_done", false),
            createdAt = created,
            completedAt = Dates.parseIso(r.optString("completed_at", null)),
            reminderAt = Dates.parseIso(r.optString("reminder_at", null)),
            lastFiredAt = null,
            repeatRule = RepeatRule.fromKey(r.optString("repeat_rule", "none")),
            updatedAt = Dates.parseIso(r.optString("updated_at", null)) ?: created,
            deletedAt = Dates.parseIso(r.optString("deleted_at", null)),
            dirty = false,
        )
    }
}
