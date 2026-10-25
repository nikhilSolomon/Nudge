package dev.nudge.android.ui

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings as AndroidSettings
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Error
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ExposedDropdownMenuAnchorType
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.nudge.android.Graph
import dev.nudge.android.data.Dates
import dev.nudge.android.data.ReminderStyle
import dev.nudge.android.data.Settings
import dev.nudge.android.reminders.ReminderNotifications
import dev.nudge.android.reminders.ReminderScheduler
import dev.nudge.android.sync.SyncStatus
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(onBack: () -> Unit) {
    val settings = Graph.settings
    val s by settings.state.collectAsStateWithLifecycle()
    val context = LocalContext.current

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Settings") },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") } },
            )
        },
    ) { padding ->
        Column(
            Modifier.padding(padding).fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Section("When a reminder is due") {
                SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                    ReminderStyle.entries.forEachIndexed { i, style ->
                        SegmentedButton(
                            selected = s.reminderStyle == style,
                            onClick = { settings.update { it.copy(reminderStyle = style) } },
                            shape = SegmentedButtonDefaults.itemShape(i, ReminderStyle.entries.size),
                        ) { Text(style.label, maxLines = 1) }
                    }
                }
                Text(
                    when (s.reminderStyle) {
                        ReminderStyle.FULLSCREEN -> "Opens a full-screen alarm-style page, even over the lock screen."
                        ReminderStyle.NOTIFICATION -> "A normal high-priority notification with Done and Snooze."
                        ReminderStyle.BOTH -> "Full-screen page plus a notification you can act on from the shade."
                    },
                    style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                SwitchRow("Vibrate", s.vibrate) { settings.update { st -> st.copy(vibrate = it) } }
            }

            Section("Snooze buttons") {
                s.snoozeMinutes.forEachIndexed { i, minutes ->
                    DropdownRow("Button ${i + 1}", Settings.snoozeChoices.map { it to Dates.minutesLabel(it) }, minutes) { v ->
                        settings.update { st -> st.copy(snoozeMinutes = st.snoozeMinutes.toMutableList().also { it[i] = v }) }
                    }
                }
            }

            Section("List") {
                SwitchRow("Group tasks by day", s.groupByDate) { settings.update { st -> st.copy(groupByDate = it) } }
                SwitchRow("Show completed section", s.showCompleted) { settings.update { st -> st.copy(showCompleted = it) } }
            }

            Section("Preset times") {
                DropdownRow("“Tomorrow” time", (0..23).map { it to Dates.hourLabel(it) }, s.morningHour) { v ->
                    settings.update { st -> st.copy(morningHour = v) }
                }
                DropdownRow("“This evening” time", (0..23).map { it to Dates.hourLabel(it) }, s.eveningHour) { v ->
                    settings.update { st -> st.copy(eveningHour = v) }
                }
            }

            PermissionsSection()

            AccountSection()

            Spacer(Modifier.height(24.dp))
        }
    }
}

@Composable
private fun Section(title: String, content: @Composable () -> Unit) {
    Column {
        Text(title, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary,
            modifier = Modifier.padding(start = 4.dp, top = 12.dp, bottom = 6.dp))
        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(horizontal = 14.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) { content() }
        }
    }
}

@Composable
private fun SwitchRow(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(label, Modifier.weight(1f))
        Switch(checked = checked, onCheckedChange = onChange)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun <T> DropdownRow(label: String, options: List<Pair<T, String>>, value: T, onChange: (T) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(label, Modifier.weight(1f))
        ExposedDropdownMenuBox(expanded = open, onExpandedChange = { open = it }) {
            OutlinedTextField(
                value = options.firstOrNull { it.first == value }?.second ?: "", onValueChange = {}, readOnly = true,
                trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = open) },
                modifier = Modifier.width(170.dp).menuAnchor(ExposedDropdownMenuAnchorType.PrimaryNotEditable),
                textStyle = MaterialTheme.typography.bodyMedium,
            )
            ExposedDropdownMenu(expanded = open, onDismissRequest = { open = false }) {
                options.forEach { (v, text) ->
                    DropdownMenuItem(text = { Text(text) }, onClick = { onChange(v); open = false })
                }
            }
        }
    }
}

@Composable
private fun PermissionsSection() {
    val context = LocalContext.current
    var tick by remember { mutableStateOf(0) }
    LifecycleResumeEffect(Unit) { tick++; onPauseOrDispose { } }

    val pkg = Uri.parse("package:${context.packageName}")
    val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
    val rows = remember(tick) {
        listOf(
            PermissionRow("Notifications", ReminderNotifications.canPost(context),
                "Needed for every reminder.") {
                context.startActivity(Intent(AndroidSettings.ACTION_APP_NOTIFICATION_SETTINGS)
                    .putExtra(AndroidSettings.EXTRA_APP_PACKAGE, context.packageName))
            },
            PermissionRow("Exact alarms", ReminderScheduler.canScheduleExact(context),
                "Fire at the exact minute, even in battery saver.") {
                if (Build.VERSION.SDK_INT >= 31) context.startActivity(Intent(AndroidSettings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, pkg))
            },
            PermissionRow("Full-screen reminders", ReminderNotifications.canUseFullScreen(context),
                "Lets the reminder page open over the lock screen.") {
                if (Build.VERSION.SDK_INT >= 34) context.startActivity(Intent(AndroidSettings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, pkg))
            },
            PermissionRow("Display over other apps", AndroidSettings.canDrawOverlays(context),
                "Lets the reminder page take over while you're using another app.") {
                context.startActivity(Intent(AndroidSettings.ACTION_MANAGE_OVERLAY_PERMISSION, pkg))
            },
            PermissionRow("Ignore battery optimisation", pm.isIgnoringBatteryOptimizations(context.packageName),
                "Recommended on Samsung so alarms aren't delayed.") {
                context.startActivity(Intent(AndroidSettings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, pkg))
            },
        )
    }

    Section("Permissions") {
        rows.forEachIndexed { i, row ->
            if (i > 0) HorizontalDivider()
            Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(if (row.granted) Icons.Default.CheckCircle else Icons.Default.Error, null,
                    tint = if (row.granted) Green else Orange)
                Spacer(Modifier.width(10.dp))
                Column(Modifier.weight(1f)) {
                    Text(row.title)
                    Text(row.detail, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                if (!row.granted) TextButton(onClick = { try { row.open() } catch (_: Exception) {} }) { Text("Grant") }
            }
        }
    }
}

private data class PermissionRow(val title: String, val granted: Boolean, val detail: String, val open: () -> Unit)

@Composable
private fun AccountSection() {
    val settings = Graph.settings
    val s by settings.state.collectAsStateWithLifecycle()
    val sync by Graph.sync.state.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }

    fun run(op: suspend () -> String?) {
        busy = true; message = null
        scope.launch {
            val r = op()
            busy = false; message = r
            if (r == null) password = ""
        }
    }

    Section("Account · sync with your Mac") {
        OutlinedTextField(value = s.supabaseUrl, onValueChange = { v -> settings.update { it.copy(supabaseUrl = v) } },
            label = { Text("Supabase project URL") }, placeholder = { Text("https://xxxx.supabase.co") },
            singleLine = true, modifier = Modifier.fillMaxWidth())
        OutlinedTextField(value = s.supabaseAnonKey, onValueChange = { v -> settings.update { it.copy(supabaseAnonKey = v) } },
            label = { Text("anon public key") }, singleLine = true, modifier = Modifier.fillMaxWidth(),
            visualTransformation = PasswordVisualTransformation())
        Text("Free at supabase.com; setup steps are in docs/SYNC.md in the project.",
            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)

        HorizontalDivider()

        if (sync.status != SyncStatus.SIGNED_OUT && sync.status != SyncStatus.NOT_CONFIGURED && Graph.sync.isSignedIn) {
            Text("Signed in as ${sync.email ?: "—"}", fontWeight = FontWeight.SemiBold)
            Text(
                when (sync.status) {
                    SyncStatus.SYNCING -> "Syncing…"
                    SyncStatus.ERROR -> "Error: ${sync.error}"
                    else -> sync.lastSyncAt?.let { "Last sync ${Dates.describe(it)}" } ?: "Up to date"
                },
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Row {
                OutlinedButton(onClick = { scope.launch { Graph.sync.syncNow() } }, enabled = sync.status != SyncStatus.SYNCING) { Text("Sync now") }
                Spacer(Modifier.weight(1f))
                TextButton(onClick = { Graph.sync.signOut() }) { Text("Sign out", color = MaterialTheme.colorScheme.error) }
            }
        } else {
            OutlinedTextField(value = email, onValueChange = { email = it }, label = { Text("Email") }, singleLine = true, modifier = Modifier.fillMaxWidth())
            OutlinedTextField(value = password, onValueChange = { password = it }, label = { Text("Password") }, singleLine = true,
                modifier = Modifier.fillMaxWidth(), visualTransformation = PasswordVisualTransformation())
            val ready = !busy && Graph.sync.isConfigured && email.isNotBlank() && password.length >= 6
            Row {
                OutlinedButton(onClick = { run { Graph.sync.signUp(email.trim(), password) } }, enabled = ready) { Text("Create account") }
                Spacer(Modifier.weight(1f))
                Button(onClick = { run { Graph.sync.signIn(email.trim(), password) } }, enabled = ready) { Text("Sign in") }
            }
            if (!Graph.sync.isConfigured) {
                Text("Fill in the project URL and anon key first.", style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            sync.error?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall) }
        }
        message?.let {
            Text(it, style = MaterialTheme.typography.bodySmall,
                color = if (it.startsWith("Account created")) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.error)
        }
    }
}
