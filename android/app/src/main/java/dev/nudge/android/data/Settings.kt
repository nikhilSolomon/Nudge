package dev.nudge.android.data

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

data class SettingsState(
    val groupByDate: Boolean = true,
    val showCompleted: Boolean = true,
    val morningHour: Int = 9,
    val eveningHour: Int = 18,
    val reminderStyle: ReminderStyle = ReminderStyle.BOTH,
    val snoozeMinutes: List<Int> = listOf(5, 15, 60),
    val vibrate: Boolean = true,
    val supabaseUrl: String = "",
    val supabaseAnonKey: String = "",
)

class Settings(context: Context) {
    private val prefs = context.getSharedPreferences("settings", Context.MODE_PRIVATE)

    private val _state = MutableStateFlow(read())
    val state: StateFlow<SettingsState> = _state
    val value: SettingsState get() = _state.value

    fun update(change: (SettingsState) -> SettingsState) {
        val s = change(_state.value)
        _state.value = s
        prefs.edit()
            .putBoolean("groupByDate", s.groupByDate)
            .putBoolean("showCompleted", s.showCompleted)
            .putInt("morningHour", s.morningHour)
            .putInt("eveningHour", s.eveningHour)
            .putString("reminderStyle", s.reminderStyle.key)
            .putString("snoozeMinutes", s.snoozeMinutes.joinToString(","))
            .putBoolean("vibrate", s.vibrate)
            .putString("supabaseUrl", s.supabaseUrl)
            .putString("supabaseAnonKey", s.supabaseAnonKey)
            .apply()
    }

    private fun read(): SettingsState {
        val snooze = prefs.getString("snoozeMinutes", null)?.split(",")?.mapNotNull { it.trim().toIntOrNull() }
        return SettingsState(
            groupByDate = prefs.getBoolean("groupByDate", true),
            showCompleted = prefs.getBoolean("showCompleted", true),
            morningHour = prefs.getInt("morningHour", 9),
            eveningHour = prefs.getInt("eveningHour", 18),
            reminderStyle = ReminderStyle.fromKey(prefs.getString("reminderStyle", null)),
            snoozeMinutes = if (snooze != null && snooze.size == 3) snooze else listOf(5, 15, 60),
            vibrate = prefs.getBoolean("vibrate", true),
            supabaseUrl = prefs.getString("supabaseUrl", "") ?: "",
            supabaseAnonKey = prefs.getString("supabaseAnonKey", "") ?: "",
        )
    }

    companion object {
        val snoozeChoices = listOf(1, 2, 3, 5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 240)
    }
}
