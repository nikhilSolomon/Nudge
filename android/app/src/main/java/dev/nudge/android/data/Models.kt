package dev.nudge.android.data

import org.json.JSONArray
import org.json.JSONObject
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.UUID

enum class RepeatRule(val key: String, val label: String, val shortLabel: String) {
    NONE("none", "Never", ""),
    DAILY("daily", "Every day", "Daily"),
    WEEKDAYS("weekdays", "Weekdays", "Weekdays"),
    WEEKLY("weekly", "Every week", "Weekly"),
    BIWEEKLY("biweekly", "Every 2 weeks", "Every 2 wks"),
    MONTHLY("monthly", "Every month", "Monthly");

    /** One period after [after] (epoch ms), keeping the local time of day. */
    fun next(after: Long): Long? {
        val z = Instant.ofEpochMilli(after).atZone(ZoneId.systemDefault())
        val n: ZonedDateTime = when (this) {
            NONE -> return null
            DAILY -> z.plusDays(1)
            WEEKDAYS -> {
                var d = z.plusDays(1)
                while (d.dayOfWeek == DayOfWeek.SATURDAY || d.dayOfWeek == DayOfWeek.SUNDAY) d = d.plusDays(1)
                d
            }
            WEEKLY -> z.plusWeeks(1)
            BIWEEKLY -> z.plusWeeks(2)
            MONTHLY -> z.plusMonths(1)
        }
        return n.toInstant().toEpochMilli()
    }

    /** First occurrence strictly after [now], stepping from [from]. */
    fun nextOccurrence(from: Long, now: Long = System.currentTimeMillis()): Long? {
        if (this == NONE) return null
        var d = from
        var guard = 0
        do {
            d = next(d) ?: return null
            guard++
        } while (d <= now && guard < 5000)
        return d
    }

    companion object {
        fun fromKey(key: String?): RepeatRule = entries.firstOrNull { it.key == key } ?: NONE
    }
}

data class Todo(
    val id: String = UUID.randomUUID().toString(),
    val title: String,
    val notes: String = "",
    val isDone: Boolean = false,
    val createdAt: Long = System.currentTimeMillis(),
    val completedAt: Long? = null,
    val reminderAt: Long? = null,
    /** Local only: when the takeover was last shown for the current reminderAt. */
    val lastFiredAt: Long? = null,
    val repeatRule: RepeatRule = RepeatRule.NONE,
    /** Last sync-relevant modification; drives last-write-wins. */
    val updatedAt: Long = createdAt,
    /** Tombstone so deletes reach other devices. */
    val deletedAt: Long? = null,
    /** Local only: needs to be pushed. */
    val dirty: Boolean = true,
) {
    val isDeleted get() = deletedAt != null
    val hasReminder get() = reminderAt != null
    val repeats get() = repeatRule != RepeatRule.NONE && reminderAt != null

    fun isOverdue(now: Long = System.currentTimeMillis()) =
        !isDone && !isDeleted && reminderAt != null && reminderAt <= now

    fun isDueToFire(now: Long = System.currentTimeMillis()): Boolean {
        if (isDone || isDeleted) return false
        val r = reminderAt ?: return false
        if (r > now) return false
        return lastFiredAt == null || lastFiredAt < r
    }

    fun toJson(): JSONObject = JSONObject().apply {
        put("id", id)
        put("title", title)
        put("notes", notes)
        put("isDone", isDone)
        put("createdAt", createdAt)
        put("completedAt", completedAt ?: JSONObject.NULL)
        put("reminderAt", reminderAt ?: JSONObject.NULL)
        put("lastFiredAt", lastFiredAt ?: JSONObject.NULL)
        put("repeatRule", repeatRule.key)
        put("updatedAt", updatedAt)
        put("deletedAt", deletedAt ?: JSONObject.NULL)
        put("dirty", dirty)
    }

    companion object {
        fun fromJson(o: JSONObject): Todo {
            val created = o.optLong("createdAt", System.currentTimeMillis())
            return Todo(
                id = o.optString("id", UUID.randomUUID().toString()),
                title = o.optString("title", ""),
                notes = o.optString("notes", ""),
                isDone = o.optBoolean("isDone", false),
                createdAt = created,
                completedAt = o.optLongOrNull("completedAt"),
                reminderAt = o.optLongOrNull("reminderAt"),
                lastFiredAt = o.optLongOrNull("lastFiredAt"),
                repeatRule = RepeatRule.fromKey(o.optString("repeatRule", "none")),
                updatedAt = o.optLong("updatedAt", created),
                deletedAt = o.optLongOrNull("deletedAt"),
                dirty = o.optBoolean("dirty", true),
            )
        }

        fun listFromJson(text: String): List<Todo> = try {
            val arr = JSONArray(text)
            (0 until arr.length()).map { fromJson(arr.getJSONObject(it)) }
        } catch (_: Exception) {
            emptyList()
        }

        fun listToJson(list: List<Todo>): String = JSONArray().apply { list.forEach { put(it.toJson()) } }.toString()
    }
}

private fun JSONObject.optLongOrNull(key: String): Long? = if (isNull(key) || !has(key)) null else optLong(key)

enum class DayGroup(val title: String) {
    OVERDUE("Overdue"), TODAY("Today"), TOMORROW("Tomorrow"), THIS_WEEK("Next 7 days"), LATER("Later"), NO_DATE("No date");

    companion object {
        fun classify(reminderAt: Long?, now: Long = System.currentTimeMillis()): DayGroup {
            reminderAt ?: return NO_DATE
            if (reminderAt <= now) return OVERDUE
            val zone = ZoneId.systemDefault()
            val date = Instant.ofEpochMilli(reminderAt).atZone(zone).toLocalDate()
            val today = Instant.ofEpochMilli(now).atZone(zone).toLocalDate()
            return when {
                date == today -> TODAY
                date == today.plusDays(1) -> TOMORROW
                date < today.plusDays(7) -> THIS_WEEK
                else -> LATER
            }
        }
    }
}

enum class ReminderStyle(val key: String, val label: String) {
    FULLSCREEN("fullscreen", "Screen takeover"),
    NOTIFICATION("notification", "Notification"),
    BOTH("both", "Both");

    val usesFullscreen get() = this != NOTIFICATION
    val usesNotification get() = this != FULLSCREEN

    companion object {
        fun fromKey(k: String?) = entries.firstOrNull { it.key == k } ?: BOTH
    }
}

object Dates {
    private val time = DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT)
    private val day = DateTimeFormatter.ofPattern("EEE, MMM d")
    private val zone get() = ZoneId.systemDefault()

    /** "Today 3:45 PM", "Tomorrow 9:00 AM", "Mon, Oct 5 · 3:00 PM" */
    fun describe(epochMs: Long, now: Long = System.currentTimeMillis()): String {
        val z = Instant.ofEpochMilli(epochMs).atZone(zone)
        val today = Instant.ofEpochMilli(now).atZone(zone).toLocalDate()
        val t = time.format(z)
        return when (z.toLocalDate()) {
            today -> "Today $t"
            today.plusDays(1) -> "Tomorrow $t"
            today.minusDays(1) -> "Yesterday $t"
            else -> "${day.format(z)} · $t"
        }
    }

    fun timeOnly(epochMs: Long): String = time.format(Instant.ofEpochMilli(epochMs).atZone(zone))

    fun hourLabel(hour: Int): String = time.format(LocalTime.of(hour, 0))

    fun nextOccurrence(hour: Int, minute: Int = 0): Long {
        val now = ZonedDateTime.now(zone)
        var t = now.with(LocalTime.of(hour, minute))
        if (!t.isAfter(now)) t = t.plusDays(1)
        return t.toInstant().toEpochMilli()
    }

    fun tomorrow(hour: Int, minute: Int = 0): Long =
        ZonedDateTime.now(zone).plusDays(1).with(LocalTime.of(hour, minute)).toInstant().toEpochMilli()

    fun roundedUpToFiveMinutes(): Long {
        val now = ZonedDateTime.now(zone).withSecond(0).withNano(0)
        val add = 5 - (now.minute % 5)
        return now.plusMinutes(add.toLong()).toInstant().toEpochMilli()
    }

    fun combine(date: LocalDate, hour: Int, minute: Int): Long =
        date.atTime(hour, minute).atZone(zone).toInstant().toEpochMilli()

    fun iso(epochMs: Long): String = DateTimeFormatter.ISO_INSTANT.format(Instant.ofEpochMilli(epochMs))

    /** Parses Postgres timestamptz text such as 2026-10-25T10:20:30.123456+00:00. */
    fun parseIso(text: String?): Long? {
        if (text.isNullOrBlank()) return null
        return try {
            OffsetDateTime.parse(text).toInstant().toEpochMilli()
        } catch (_: Exception) {
            try { Instant.parse(text).toEpochMilli() } catch (_: Exception) { null }
        }
    }

    fun minutesLabel(minutes: Int): String {
        if (minutes < 60) return "$minutes min"
        val h = minutes / 60.0
        val text = if (h == h.toLong().toDouble()) h.toLong().toString() else String.format("%.1f", h)
        return "$text ${if (h == 1.0) "hour" else "hours"}"
    }

    @Suppress("unused")
    val utc: ZoneOffset = ZoneOffset.UTC
}
