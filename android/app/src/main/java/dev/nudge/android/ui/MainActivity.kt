package dev.nudge.android.ui

import android.Manifest
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.lifecycle.compose.LifecycleResumeEffect
import dev.nudge.android.Graph
import dev.nudge.android.reminders.ReminderScheduler
import kotlinx.coroutines.launch
import androidx.compose.runtime.rememberCoroutineScope

enum class Screen { LIST, SETTINGS }

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Graph.ensure(this)
        enableEdgeToEdge()
        setContent {
            NudgeTheme {
                Root()
            }
        }
    }
}

@Composable
private fun Root() {
    var screen by rememberSaveable { mutableStateOf(Screen.LIST) }
    val scope = rememberCoroutineScope()

    val notifPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { }
    LaunchedEffect(Unit) {
        if (Build.VERSION.SDK_INT >= 33) notifPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
    }

    // Every time we come back to the foreground: pull from the server and re-arm alarms.
    val context = androidx.compose.ui.platform.LocalContext.current
    LifecycleResumeEffect(Unit) {
        scope.launch { Graph.sync.syncNow() }
        ReminderScheduler.reschedule(context)
        onPauseOrDispose { }
    }

    when (screen) {
        Screen.LIST -> TodoListScreen(onOpenSettings = { screen = Screen.SETTINGS })
        Screen.SETTINGS -> {
            BackHandler { screen = Screen.LIST }
            SettingsScreen(onBack = { screen = Screen.LIST })
        }
    }
}
