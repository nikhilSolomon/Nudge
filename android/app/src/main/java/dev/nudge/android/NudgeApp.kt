package dev.nudge.android

import android.app.Application
import android.content.Context
import androidx.work.Configuration
import androidx.work.WorkManager
import dev.nudge.android.data.Settings
import dev.nudge.android.data.TodoRepository
import dev.nudge.android.reminders.ReminderNotifications
import dev.nudge.android.reminders.ReminderScheduler
import dev.nudge.android.sync.SyncManager
import dev.nudge.android.sync.SyncWorker

class NudgeApp : Application() {
    override fun onCreate() {
        super.onCreate()
        Graph.init(this)
        ReminderNotifications.ensureChannels(this)
        SyncWorker.schedulePeriodic(this)
    }
}

/** Tiny service locator so receivers, workers and UI share one repository/settings/sync. */
object Graph {
    @Volatile private var initialized = false
    lateinit var repo: TodoRepository
        private set
    lateinit var settings: Settings
        private set
    lateinit var sync: SyncManager
        private set

    @Synchronized
    fun init(context: Context) {
        if (initialized) return
        val app = context.applicationContext
        if (!WorkManager.isInitialized()) {
            WorkManager.initialize(app, Configuration.Builder().build())
        }
        settings = Settings(app)
        repo = TodoRepository(app)
        sync = SyncManager(app, repo, settings)
        repo.onChanged = {
            ReminderScheduler.reschedule(app)
            sync.scheduleSoon()
        }
        initialized = true
        ReminderScheduler.reschedule(app)
    }

    fun ensure(context: Context) = init(context)
}
