package dev.nudge.android.reminders

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import dev.nudge.android.Graph
import dev.nudge.android.R
import dev.nudge.android.data.Dates
import dev.nudge.android.data.Todo

object ReminderNotifications {
    const val CHANNEL = "reminders"

    fun ensureChannels(context: Context) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(CHANNEL, "Reminders", NotificationManager.IMPORTANCE_HIGH).apply {
            description = "Due reminders. High importance so they can take over the screen."
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 400, 200, 400)
            setSound(
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION),
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_EVENT)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        nm.createNotificationChannel(channel)
    }

    fun canPost(context: Context): Boolean =
        Build.VERSION.SDK_INT < 33 ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    fun canUseFullScreen(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < 34) return true
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        return nm.canUseFullScreenIntent()
    }

    fun show(context: Context, todo: Todo, fullScreen: Boolean) {
        if (!canPost(context)) return
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val snooze = Graph.settings.value.snoozeMinutes.firstOrNull() ?: 5

        val open = PendingIntent.getActivity(
            context, todo.id.hashCode(), ReminderActivity.intent(context, listOf(todo.id)),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val lines = buildList {
            if (todo.notes.isNotBlank()) add(todo.notes)
            todo.reminderAt?.let { add(Dates.describe(it)) }
            if (todo.repeats) add("Repeats · ${todo.repeatRule.shortLabel}")
        }

        val builder = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(todo.title)
            .setContentText(lines.firstOrNull() ?: "Reminder")
            .setStyle(NotificationCompat.BigTextStyle().bigText(lines.joinToString("\n")))
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(if (fullScreen) NotificationCompat.CATEGORY_ALARM else NotificationCompat.CATEGORY_REMINDER)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setAutoCancel(true)
            .setOngoing(false)
            .setContentIntent(open)
            .setDeleteIntent(action(context, ReminderReceiver.ACTION_DISMISS, todo.id, 0))
            .addAction(0, "Done", action(context, ReminderReceiver.ACTION_DONE, todo.id, 1))
            .addAction(0, "Snooze ${Dates.minutesLabel(snooze)}",
                action(context, ReminderReceiver.ACTION_SNOOZE, todo.id, 2, snooze))

        if (fullScreen) {
            builder.setFullScreenIntent(open, true)
        }
        nm.notify(todo.id.hashCode(), builder.build())
    }

    fun cancel(context: Context, id: String) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(id.hashCode())
    }

    private fun action(context: Context, action: String, id: String, slot: Int, minutes: Int = 0): PendingIntent =
        PendingIntent.getBroadcast(
            context, id.hashCode() * 4 + slot,
            Intent(context, ReminderReceiver::class.java)
                .setAction(action)
                .putExtra(ReminderReceiver.EXTRA_ID, id)
                .putExtra(ReminderReceiver.EXTRA_MINUTES, minutes),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
}
