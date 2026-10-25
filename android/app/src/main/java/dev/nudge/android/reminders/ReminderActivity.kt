package dev.nudge.android.reminders

import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.Repeat
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.nudge.android.Graph
import dev.nudge.android.data.Dates
import dev.nudge.android.data.Todo
import dev.nudge.android.ui.NudgeTheme

/** Full-screen takeover shown over the lock screen (and over other apps when permitted). */
class ReminderActivity : ComponentActivity() {
    private val queue = mutableStateListOf<String>()
    private var ringtone: Ringtone? = null
    private val handler = Handler(Looper.getMainLooper())
    private val chimeAgain = object : Runnable {
        override fun run() {
            chime()
            handler.postDelayed(this, 30_000)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Graph.ensure(this)
        current = this

        setShowWhenLocked(true)
        setTurnScreenOn(true)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        (getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager).requestDismissKeyguard(this, null)

        addIds(intent)

        setContent {
            NudgeTheme(dark = true) {
                val id = queue.firstOrNull()
                val todo = id?.let { Graph.repo.get(it) }
                if (todo == null) {
                    finishIfEmpty()
                } else {
                    BackHandler { act(todo.id) { } }
                    TakeoverScreen(
                        todo = todo,
                        snoozeMinutes = Graph.settings.value.snoozeMinutes,
                        onDone = { act(todo.id) { Graph.repo.complete(todo.id) } },
                        onSnooze = { min -> act(todo.id) { Graph.repo.snooze(todo.id, min * 60_000L) } },
                        onDismiss = { act(todo.id) { } },
                    )
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        addIds(intent)
    }

    override fun onStart() {
        super.onStart()
        chime()
        handler.postDelayed(chimeAgain, 30_000)
    }

    override fun onStop() {
        super.onStop()
        handler.removeCallbacks(chimeAgain)
        ringtone?.stop()
    }

    override fun onDestroy() {
        if (current === this) current = null
        super.onDestroy()
    }

    private fun addIds(intent: Intent?) {
        val ids = intent?.getStringArrayExtra(EXTRA_IDS) ?: return
        ids.forEach { if (it !in queue && Graph.repo.get(it)?.isDone == false) queue.add(it) }
        finishIfEmpty()
    }

    private fun act(id: String, change: () -> Unit) {
        change()
        ReminderNotifications.cancel(this, id)
        queue.remove(id)
        finishIfEmpty()
    }

    private fun finishIfEmpty() {
        if (queue.none { Graph.repo.get(it)?.isDone == false }) finish()
    }

    private fun chime() {
        try {
            if (ringtone == null) {
                ringtone = RingtoneManager.getRingtone(this, RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION))?.apply {
                    audioAttributes = AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                }
            }
            ringtone?.play()
            if (Graph.settings.value.vibrate) {
                val vibrator = if (Build.VERSION.SDK_INT >= 31) {
                    (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
                } else {
                    @Suppress("DEPRECATION")
                    getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
                }
                vibrator.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 400, 200, 400), -1))
            }
        } catch (_: Exception) {
        }
    }

    companion object {
        private const val EXTRA_IDS = "ids"
        @Volatile private var current: ReminderActivity? = null

        fun intent(context: Context, ids: List<String>): Intent =
            Intent(context, ReminderActivity::class.java)
                .putExtra(EXTRA_IDS, ids.toTypedArray())
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)

        /** Done/Snooze tapped on the notification while the takeover is up: drop it from the queue. */
        fun closeIfShowing(context: Context, id: String) {
            val a = current ?: return
            a.handler.post {
                a.queue.remove(id)
                a.finishIfEmpty()
            }
        }
    }
}

@Composable
private fun TakeoverScreen(
    todo: Todo,
    snoozeMinutes: List<Int>,
    onDone: () -> Unit,
    onSnooze: (Int) -> Unit,
    onDismiss: () -> Unit,
) {
    val pulse = rememberInfiniteTransition(label = "pulse")
    val scale by pulse.animateFloat(
        0.9f, 1.25f, infiniteRepeatable(tween(900), RepeatMode.Reverse), label = "scale",
    )
    val tilt by pulse.animateFloat(
        -12f, 12f, infiniteRepeatable(tween(900), RepeatMode.Reverse), label = "tilt",
    )
    val orange = Color(0xFFF59E0B)

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFF0E0E10))
            .systemBarsPadding(),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 28.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            Box(contentAlignment = Alignment.Center) {
                Box(
                    Modifier
                        .size(140.dp)
                        .scale(scale)
                        .background(orange.copy(alpha = 0.15f), CircleShape),
                )
                Box(Modifier.size(108.dp).background(orange.copy(alpha = 0.25f), CircleShape))
                Icon(
                    Icons.Default.Notifications, null, tint = orange,
                    modifier = Modifier.size(56.dp).graphicsLayer { rotationZ = tilt },
                )
            }

            Text("REMINDER", color = Color.White.copy(alpha = 0.55f), fontSize = 13.sp,
                fontWeight = FontWeight.SemiBold, letterSpacing = 2.sp)

            Text(
                todo.title, color = Color.White, fontSize = 32.sp, lineHeight = 38.sp,
                fontWeight = FontWeight.Bold, textAlign = TextAlign.Center,
            )

            if (todo.notes.isNotBlank()) {
                Text(todo.notes, color = Color.White.copy(alpha = 0.7f), fontSize = 16.sp,
                    textAlign = TextAlign.Center, lineHeight = 22.sp)
            }

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                todo.reminderAt?.let { Text(Dates.describe(it), color = Color.White.copy(alpha = 0.45f), fontSize = 14.sp) }
                if (todo.repeats) {
                    Icon(Icons.Default.Repeat, null, tint = Color.White.copy(alpha = 0.45f), modifier = Modifier.size(14.dp))
                    Text(todo.repeatRule.shortLabel, color = Color.White.copy(alpha = 0.45f), fontSize = 14.sp)
                }
            }

            Spacer(Modifier.height(8.dp))

            Button(
                onClick = onDone,
                modifier = Modifier.fillMaxWidth().height(56.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF34C759), contentColor = Color.White),
            ) {
                Icon(Icons.Default.Check, null)
                Spacer(Modifier.size(8.dp))
                Text(if (todo.repeats) "Done · schedule next" else "Mark as done", fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
            }

            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                snoozeMinutes.take(3).forEach { m ->
                    FilledTonalButton(
                        onClick = { onSnooze(m) },
                        modifier = Modifier.weight(1f).height(52.dp),
                        colors = ButtonDefaults.filledTonalButtonColors(
                            containerColor = Color.White.copy(alpha = 0.1f), contentColor = Color.White),
                    ) {
                        Text(Dates.minutesLabel(m), fontSize = 14.sp)
                    }
                }
            }

            TextButton(onClick = onDismiss) {
                Text("Dismiss", color = Color.White.copy(alpha = 0.55f))
            }
        }
    }
}
