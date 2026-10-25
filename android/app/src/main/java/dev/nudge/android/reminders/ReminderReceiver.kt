package dev.nudge.android.reminders

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Settings
import dev.nudge.android.Graph

/** Handles the alarm firing and the Done / Snooze / Dismiss actions from notifications. */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Graph.ensure(context)
        val repo = Graph.repo
        when (intent.action) {
            ReminderScheduler.ACTION_FIRE -> {
                fireDue(context)
                ReminderScheduler.reschedule(context)
            }
            ACTION_DONE -> intent.getStringExtra(EXTRA_ID)?.let { id ->
                repo.complete(id)
                ReminderNotifications.cancel(context, id)
                ReminderActivity.closeIfShowing(context, id)
            }
            ACTION_SNOOZE -> intent.getStringExtra(EXTRA_ID)?.let { id ->
                val minutes = intent.getIntExtra(EXTRA_MINUTES, 5)
                repo.snooze(id, minutes * 60_000L)
                ReminderNotifications.cancel(context, id)
                ReminderActivity.closeIfShowing(context, id)
            }
            ACTION_DISMISS -> intent.getStringExtra(EXTRA_ID)?.let { id ->
                ReminderNotifications.cancel(context, id)
            }
        }
    }

    companion object {
        const val ACTION_DONE = "dev.nudge.android.DONE"
        const val ACTION_SNOOZE = "dev.nudge.android.SNOOZE"
        const val ACTION_DISMISS = "dev.nudge.android.DISMISS"
        const val EXTRA_ID = "id"
        const val EXTRA_MINUTES = "minutes"

        /** Show everything that is due: notification (with full-screen intent) and/or the takeover activity. */
        fun fireDue(context: Context) {
            Graph.ensure(context)
            val repo = Graph.repo
            val due = repo.dueToFire()
            if (due.isEmpty()) return
            due.forEach { repo.markFired(it.id) }

            val style = Graph.settings.value.reminderStyle
            // The notification is always posted when the takeover is wanted: its full-screen intent is
            // what launches the activity when the screen is off or locked.
            due.forEach { ReminderNotifications.show(context, it, fullScreen = style.usesFullscreen) }

            // While the phone is unlocked and in use, Android downgrades full-screen intents to a
            // heads-up banner. With "Display over other apps" granted we may start the activity directly.
            if (style.usesFullscreen && Settings.canDrawOverlays(context)) {
                context.startActivity(ReminderActivity.intent(context, due.map { it.id }))
            }
        }
    }
}
