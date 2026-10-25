package dev.nudge.android.sync

import android.content.Context
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import dev.nudge.android.Graph
import dev.nudge.android.reminders.ReminderScheduler
import java.util.concurrent.TimeUnit

/** Background pull every ~15 minutes so reminders set on the Mac reach the phone while it's idle. */
class SyncWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        Graph.ensure(applicationContext)
        if (!Graph.sync.isSignedIn) return Result.success()
        Graph.sync.syncNow()
        ReminderScheduler.reschedule(applicationContext)
        return Result.success()
    }

    companion object {
        fun schedulePeriodic(context: Context) {
            val request = PeriodicWorkRequestBuilder<SyncWorker>(15, TimeUnit.MINUTES)
                .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                .build()
            WorkManager.getInstance(context)
                .enqueueUniquePeriodicWork("sync", ExistingPeriodicWorkPolicy.KEEP, request)
        }
    }
}
