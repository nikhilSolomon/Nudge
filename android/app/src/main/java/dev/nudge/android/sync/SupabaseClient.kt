package dev.nudge.android.sync

import android.content.Context
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.util.concurrent.TimeUnit

data class SupabaseSession(
    val accessToken: String,
    val refreshToken: String,
    val expiresAtMs: Long,
    val userId: String,
    val email: String,
) {
    val isExpiringSoon get() = expiresAtMs - System.currentTimeMillis() < 60_000

    fun toJson() = JSONObject()
        .put("accessToken", accessToken).put("refreshToken", refreshToken)
        .put("expiresAtMs", expiresAtMs).put("userId", userId).put("email", email)

    companion object {
        fun fromJson(s: String?): SupabaseSession? = try {
            val o = JSONObject(s ?: return null)
            SupabaseSession(o.getString("accessToken"), o.getString("refreshToken"),
                o.getLong("expiresAtMs"), o.optString("userId"), o.optString("email"))
        } catch (_: Exception) { null }
    }
}

class SupabaseException(message: String, val status: Int) : IOException(message)

/** Thin Supabase Auth + PostgREST client over OkHttp. All calls are blocking; run them on IO. */
class SupabaseClient(context: Context, baseUrl: String, private val anonKey: String) {
    private val base = baseUrl.trim().trimEnd('/')
    private val prefs = context.getSharedPreferences("sync", Context.MODE_PRIVATE)
    private val http = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(20, TimeUnit.SECONDS)
        .build()
    private val json = "application/json; charset=utf-8".toMediaType()

    @Volatile var session: SupabaseSession? = SupabaseSession.fromJson(prefs.getString("session", null))
        private set

    val isSignedIn get() = session != null

    // MARK: auth

    /** Returns null when the account was created but email confirmation is still required. */
    fun signUp(email: String, password: String): SupabaseSession? {
        val body = send("auth/v1/signup", "POST", body = JSONObject().put("email", email).put("password", password), auth = false)
        return parseSession(body)?.also { store(it) }
    }

    fun signIn(email: String, password: String): SupabaseSession {
        val body = send("auth/v1/token", "POST", query = mapOf("grant_type" to "password"),
            body = JSONObject().put("email", email).put("password", password), auth = false)
        val s = parseSession(body) ?: throw SupabaseException("Sign-in response had no session.", 200)
        store(s)
        return s
    }

    fun signOut() {
        val s = session
        session = null
        prefs.edit().remove("session").apply()
        if (s != null) {
            try { send("auth/v1/logout", "POST", auth = true, bearer = s.accessToken) } catch (_: Exception) {}
        }
    }

    fun refreshIfNeeded() {
        val s = session ?: return
        if (!s.isExpiringSoon) return
        val body = send("auth/v1/token", "POST", query = mapOf("grant_type" to "refresh_token"),
            body = JSONObject().put("refresh_token", s.refreshToken), auth = false)
        val fresh = parseSession(body) ?: throw SupabaseException("Could not refresh session.", 401)
        store(fresh)
    }

    private fun store(s: SupabaseSession) {
        session = s
        prefs.edit().putString("session", s.toJson().toString()).apply()
    }

    private fun parseSession(body: String): SupabaseSession? {
        val o = try { JSONObject(body) } catch (_: Exception) { return null }
        val access = o.optString("access_token", "")
        val refresh = o.optString("refresh_token", "")
        if (access.isEmpty() || refresh.isEmpty()) return null
        val user = o.optJSONObject("user")
        val expiresAt = when {
            o.has("expires_at") -> o.getLong("expires_at") * 1000
            o.has("expires_in") -> System.currentTimeMillis() + o.getLong("expires_in") * 1000
            else -> System.currentTimeMillis() + 3_600_000
        }
        return SupabaseSession(access, refresh, expiresAt, user?.optString("id") ?: "", user?.optString("email") ?: "")
    }

    // MARK: PostgREST

    fun select(table: String, query: Map<String, String>): JSONArray {
        refreshIfNeeded()
        val q = query.toMutableMap()
        q.putIfAbsent("select", "*")
        val body = send("rest/v1/$table", "GET", query = q, auth = true)
        return JSONArray(body)
    }

    fun upsert(table: String, rows: JSONArray, conflictColumn: String = "id") {
        if (rows.length() == 0) return
        refreshIfNeeded()
        send("rest/v1/$table", "POST", query = mapOf("on_conflict" to conflictColumn), bodyText = rows.toString(),
            auth = true, headers = mapOf("Prefer" to "resolution=merge-duplicates,return=minimal"))
    }

    // MARK: transport

    private fun send(
        path: String, method: String, query: Map<String, String> = emptyMap(),
        body: JSONObject? = null, bodyText: String? = null,
        auth: Boolean, bearer: String? = null, headers: Map<String, String> = emptyMap(),
    ): String {
        val urlBuilder = StringBuilder("$base/$path")
        if (query.isNotEmpty()) {
            urlBuilder.append('?')
            urlBuilder.append(query.entries.joinToString("&") {
                "${java.net.URLEncoder.encode(it.key, "UTF-8")}=${java.net.URLEncoder.encode(it.value, "UTF-8")}"
            })
        }
        val token = bearer ?: (if (auth) session?.accessToken else null) ?: anonKey
        val payload = bodyText ?: body?.toString()
        val req = Request.Builder()
            .url(urlBuilder.toString())
            .header("apikey", anonKey)
            .header("Authorization", "Bearer $token")
            .header("Accept", "application/json")
            .apply { headers.forEach { (k, v) -> header(k, v) } }
            .method(method, payload?.toRequestBody(json) ?: if (method == "POST") "".toRequestBody(json) else null)
            .build()

        http.newCall(req).execute().use { resp ->
            val text = resp.body?.string() ?: ""
            if (!resp.isSuccessful) throw SupabaseException(errorMessage(text, resp.code), resp.code)
            return text
        }
    }

    private fun errorMessage(text: String, status: Int): String {
        try {
            val o = JSONObject(text)
            for (k in listOf("error_description", "msg", "message", "error", "hint", "details")) {
                val v = o.optString(k, "")
                if (v.isNotEmpty()) return v
            }
        } catch (_: Exception) {}
        return text.ifBlank { "HTTP $status" }
    }
}
