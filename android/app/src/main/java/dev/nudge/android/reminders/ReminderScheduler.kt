package dev.nudge.android.reminders

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import dev.nudge.android.Graph
import dev.nudge.android.ui.MainActivity

/** One exact alarm for the earliest reminder that hasn't been shown yet. */
object ReminderScheduler {
    const val ACTION_FIRE = "dev.nudge.android.FIRE"

    fun reschedule(context: Context) {
        Graph.ensure(context)
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pi = firePendingIntent(context)
        am.cancel(pi)

        val now = System.currentTimeMillis()
        val next = Graph.repo.nextAlarmTime(now) ?: return
        val at = maxOf(next, now + 1000)

        val show = PendingIntent.getActivity(
            context, 1, Intent(context, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        if (canScheduleExact(context)) {
            // Alarm-clock semantics: fires in Doze, shows the alarm icon in the status bar.
            am.setAlarmClock(AlarmManager.AlarmClockInfo(at, show), pi)
        } else {
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
        }
    }

    fun canScheduleExact(context: Context): Boolean {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        return Build.VERSION.SDK_INT < 31 || am.canScheduleExactAlarms()
    }

    private fun firePendingIntent(context: Context): PendingIntent =
        PendingIntent.getBroadcast(
            context, 0,
            Intent(context, ReminderReceiver::class.java).setAction(ACTION_FIRE),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
}
