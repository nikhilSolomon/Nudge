package dev.nudge.android.reminders

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Reboot, time changes, app update: fire anything missed and re-arm the alarm. */
class SystemEventsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        ReminderReceiver.fireDue(context)
        ReminderScheduler.reschedule(context)
    }
}
