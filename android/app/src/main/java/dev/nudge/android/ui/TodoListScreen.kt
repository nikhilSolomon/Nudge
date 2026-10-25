package dev.nudge.android.ui

import android.content.Context
import android.provider.Settings as AndroidSettings
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.automirrored.filled.Notes
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.NotificationsActive
import androidx.compose.material.icons.filled.Repeat
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material.icons.outlined.Verified
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.ExposedDropdownMenuAnchorType
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.nudge.android.Graph
import dev.nudge.android.data.Dates
import dev.nudge.android.data.DayGroup
import dev.nudge.android.data.RepeatRule
import dev.nudge.android.data.Todo
import dev.nudge.android.reminders.ReminderNotifications
import dev.nudge.android.reminders.ReminderScheduler
import kotlinx.coroutines.delay

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TodoListScreen(onOpenSettings: () -> Unit) {
    val repo = Graph.repo
    val todosAll by repo.todos.collectAsStateWithLifecycle()
    val settings by Graph.settings.state.collectAsStateWithLifecycle()
    var editing by remember { mutableStateOf<Todo?>(null) }
    var showCompleted by rememberSaveable { mutableStateOf(true) }

    // Re-group every 30 s so "Overdue"/"Today" stay correct without a change.
    var now by remember { mutableStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) { while (true) { delay(30_000); now = System.currentTimeMillis() } }

    val pending = remember(todosAll, now) { repo.pending() }
    val grouped = remember(todosAll, now) { repo.grouped(now) }
    val completed = remember(todosAll) { repo.completed() }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Row(verticalAlignment = Alignment.Bottom) {
                        Text("Nudge", fontWeight = FontWeight.Bold)
                        Spacer(Modifier.width(10.dp))
                        Text(
                            if (pending.isEmpty()) "All clear" else "${pending.size} to do",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(bottom = 3.dp),
                        )
                    }
                },
                actions = { IconButton(onClick = onOpenSettings) { Icon(Icons.Default.Settings, "Settings") } },
            )
        },
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize().imePadding()) {
            PermissionBanner(onFix = onOpenSettings)
            AddBar(onAdd = { title, notes, reminder, repeat -> repo.add(title, notes, reminder, repeat) })

            if (pending.isEmpty() && completed.isEmpty()) {
                EmptyState()
            } else {
                LazyColumn(contentPadding = PaddingValues(bottom = 32.dp)) {
                    if (settings.groupByDate) {
                        grouped.forEach { (group, items) ->
                            item(key = "h-${group.name}") { GroupHeader(group, items.size) }
                            items(items, key = { it.id }) { todo ->
                                TodoRow(todo, now, onToggle = { repo.toggleDone(todo.id) }, onClick = { editing = todo })
                            }
                        }
                    } else {
                        items(pending, key = { it.id }) { todo ->
                            TodoRow(todo, now, onToggle = { repo.toggleDone(todo.id) }, onClick = { editing = todo })
                        }
                    }
                    if (settings.showCompleted && completed.isNotEmpty()) {
                        item(key = "h-completed") {
                            Row(
                                Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Row(
                                    Modifier.clickable { showCompleted = !showCompleted },
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    Icon(Icons.Default.ExpandMore, null, Modifier.size(18.dp).rotate(if (showCompleted) 0f else -90f),
                                        tint = MaterialTheme.colorScheme.onSurfaceVariant)
                                    Text("Completed · ${completed.size}", style = MaterialTheme.typography.labelLarge,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                                Spacer(Modifier.weight(1f))
                                TextButton(onClick = { repo.clearCompleted() }) { Text("Clear") }
                            }
                        }
                        if (showCompleted) {
                            items(completed, key = { it.id }) { todo ->
                                TodoRow(todo, now, onToggle = { repo.toggleDone(todo.id) }, onClick = { editing = todo })
                            }
                        }
                    }
                }
            }
        }
    }

    editing?.let { todo ->
        val live = todosAll.firstOrNull { it.id == todo.id } ?: todo
        TodoEditorSheet(
            todo = live,
            onDismiss = { editing = null },
            onSave = { repo.replace(it); editing = null },
            onDelete = { repo.delete(live.id); editing = null },
        )
    }
}

@Composable
private fun PermissionBanner(onFix: () -> Unit) {
    val context = LocalContext.current
    val missing = remember { missingPermissions(context) }
    if (missing.isEmpty()) return
    Card(
        Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp),
        colors = CardDefaults.cardColors(containerColor = Orange.copy(alpha = 0.15f)),
    ) {
        Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Default.Warning, null, tint = Orange)
            Spacer(Modifier.width(10.dp))
            Column(Modifier.weight(1f)) {
                Text("Reminders need permission", fontWeight = FontWeight.SemiBold)
                Text(missing.joinToString(", "), style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            TextButton(onClick = onFix) { Text("Fix") }
        }
    }
}

fun missingPermissions(context: Context): List<String> = buildList {
    if (!ReminderNotifications.canPost(context)) add("Notifications")
    if (!ReminderScheduler.canScheduleExact(context)) add("Exact alarms")
    if (!ReminderNotifications.canUseFullScreen(context)) add("Full-screen reminders")
    if (!AndroidSettings.canDrawOverlays(context)) add("Display over other apps")
}

@Composable
private fun AddBar(onAdd: (String, String, Long?, RepeatRule) -> Unit) {
    var title by rememberSaveable { mutableStateOf("") }
    var notes by rememberSaveable { mutableStateOf("") }
    var showNotes by rememberSaveable { mutableStateOf(false) }
    var reminder by rememberSaveable { mutableStateOf<Long?>(null) }
    var repeat by rememberSaveable { mutableStateOf(RepeatRule.NONE) }

    fun submit() {
        if (title.isBlank()) return
        onAdd(title, notes, reminder, repeat)
        title = ""; notes = ""; reminder = null; repeat = RepeatRule.NONE; showNotes = false
    }

    Card(
        Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)),
    ) {
        Column(Modifier.padding(horizontal = 8.dp, vertical = 6.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                OutlinedTextField(
                    value = title, onValueChange = { title = it },
                    placeholder = { Text("What needs doing?") },
                    singleLine = true,
                    modifier = Modifier.weight(1f),
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                    keyboardActions = KeyboardActions(onDone = { submit() }),
                    colors = androidx.compose.material3.OutlinedTextFieldDefaults.colors(
                        focusedBorderColor = Color.Transparent, unfocusedBorderColor = Color.Transparent),
                )
                IconButton(onClick = { showNotes = !showNotes }) {
                    Icon(Icons.AutoMirrored.Filled.Notes, "Details",
                        tint = if (showNotes || notes.isNotBlank()) Orange else MaterialTheme.colorScheme.onSurfaceVariant)
                }
                ReminderPicker(reminder, { reminder = it }, repeat, { repeat = it })
                IconButton(onClick = { submit() }, enabled = title.isNotBlank()) {
                    Icon(Icons.Default.Add, "Add", tint = if (title.isNotBlank()) Orange else MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            AnimatedVisibility(showNotes) {
                OutlinedTextField(
                    value = notes, onValueChange = { notes = it },
                    placeholder = { Text("Details (optional)") },
                    modifier = Modifier.fillMaxWidth().padding(bottom = 4.dp),
                    minLines = 1, maxLines = 4,
                    colors = androidx.compose.material3.OutlinedTextFieldDefaults.colors(
                        focusedBorderColor = Color.Transparent, unfocusedBorderColor = Color.Transparent),
                )
            }
            if (reminder != null) {
                Row(Modifier.padding(start = 12.dp, bottom = 6.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    AssistChip(onClick = {}, label = { Text(Dates.describe(reminder!!)) },
                        leadingIcon = { Icon(Icons.Default.Notifications, null, Modifier.size(16.dp), tint = Orange) })
                    if (repeat != RepeatRule.NONE) {
                        AssistChip(onClick = {}, label = { Text(repeat.shortLabel) },
                            leadingIcon = { Icon(Icons.Default.Repeat, null, Modifier.size(16.dp)) })
                    }
                }
            }
        }
    }
}

@Composable
private fun GroupHeader(group: DayGroup, count: Int) {
    val color = if (group == DayGroup.OVERDUE) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant
    Row(Modifier.padding(start = 20.dp, end = 16.dp, top = 14.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(group.title, style = MaterialTheme.typography.labelLarge, color = color, fontWeight = FontWeight.SemiBold)
        Spacer(Modifier.width(6.dp))
        Text("$count", style = MaterialTheme.typography.labelLarge, color = color.copy(alpha = 0.5f))
    }
}

@Composable
private fun TodoRow(todo: Todo, now: Long, onToggle: () -> Unit, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 12.dp, vertical = 6.dp),
        verticalAlignment = Alignment.Top,
    ) {
        IconButton(onClick = onToggle) {
            Icon(
                if (todo.isDone) Icons.Default.CheckCircle else Icons.Outlined.Circle,
                contentDescription = if (todo.isDone) "Mark not done" else "Mark done",
                tint = if (todo.isDone) Green else MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Column(Modifier.weight(1f).padding(top = 10.dp, end = 8.dp)) {
            Text(
                todo.title, style = MaterialTheme.typography.bodyLarge,
                textDecoration = if (todo.isDone) TextDecoration.LineThrough else null,
                color = if (todo.isDone) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onSurface,
                maxLines = 2, overflow = TextOverflow.Ellipsis,
            )
            if (todo.notes.isNotBlank()) {
                Text(todo.notes, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 2, overflow = TextOverflow.Ellipsis)
            }
            if (todo.reminderAt != null && !todo.isDone) {
                val overdue = todo.isOverdue(now)
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 2.dp)) {
                    Icon(if (overdue) Icons.Default.NotificationsActive else Icons.Outlined.Notifications, null,
                        Modifier.size(13.dp), tint = if (overdue) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant)
                    Spacer(Modifier.width(4.dp))
                    Text(Dates.describe(todo.reminderAt, now), style = MaterialTheme.typography.labelSmall,
                        color = if (overdue) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant)
                    if (todo.repeats) {
                        Spacer(Modifier.width(8.dp))
                        Icon(Icons.Default.Repeat, null, Modifier.size(12.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                        Spacer(Modifier.width(3.dp))
                        Text(todo.repeatRule.shortLabel, style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
    }
}

@Composable
private fun EmptyState() {
    val settings by Graph.settings.state.collectAsStateWithLifecycle()
    Box(Modifier.fillMaxSize().padding(bottom = 80.dp), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(Icons.Outlined.Verified, null, Modifier.size(52.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f))
            Spacer(Modifier.height(12.dp))
            Text("Nothing to do", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.height(4.dp))
            Text(
                "Add a task above. Set a reminder and Nudge will\n" +
                    if (settings.reminderStyle.usesFullscreen) "take over the screen when it's time." else "notify you when it's time.",
                style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TodoEditorSheet(todo: Todo, onDismiss: () -> Unit, onSave: (Todo) -> Unit, onDelete: () -> Unit) {
    var title by remember(todo.id) { mutableStateOf(todo.title) }
    var notes by remember(todo.id) { mutableStateOf(todo.notes) }
    var reminder by remember(todo.id) { mutableStateOf(todo.reminderAt) }
    var repeat by remember(todo.id) { mutableStateOf(todo.repeatRule) }
    var repeatMenu by remember { mutableStateOf(false) }
    val sheet = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheet) {
        Column(Modifier.padding(horizontal = 20.dp).padding(bottom = 28.dp).imePadding(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            OutlinedTextField(value = title, onValueChange = { title = it }, label = { Text("Title") },
                singleLine = true, modifier = Modifier.fillMaxWidth())
            OutlinedTextField(value = notes, onValueChange = { notes = it }, label = { Text("Notes") },
                minLines = 2, maxLines = 6, modifier = Modifier.fillMaxWidth())

            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Reminder", style = MaterialTheme.typography.labelLarge, modifier = Modifier.weight(1f))
                if (reminder != null) Text(Dates.describe(reminder!!), style = MaterialTheme.typography.bodyMedium, color = Orange)
                ReminderPicker(reminder, { reminder = it }, repeat, { repeat = it })
            }

            if (reminder != null) {
                ExposedDropdownMenuBox(expanded = repeatMenu, onExpandedChange = { repeatMenu = it }) {
                    OutlinedTextField(
                        value = repeat.label, onValueChange = {}, readOnly = true, label = { Text("Repeat") },
                        trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = repeatMenu) },
                        modifier = Modifier.fillMaxWidth().menuAnchor(ExposedDropdownMenuAnchorType.PrimaryNotEditable),
                    )
                    ExposedDropdownMenu(expanded = repeatMenu, onDismissRequest = { repeatMenu = false }) {
                        RepeatRule.entries.forEach { rule ->
                            DropdownMenuItem(text = { Text(rule.label) }, onClick = { repeat = rule; repeatMenu = false })
                        }
                    }
                }
            }

            HorizontalDivider()

            Row(verticalAlignment = Alignment.CenterVertically) {
                TextButton(onClick = onDelete, colors = androidx.compose.material3.ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error)) {
                    Icon(Icons.Default.Delete, null, Modifier.size(18.dp)); Spacer(Modifier.width(6.dp)); Text("Delete")
                }
                Spacer(Modifier.weight(1f))
                OutlinedButton(onClick = onDismiss) { Text("Cancel") }
                Spacer(Modifier.width(8.dp))
                Button(onClick = {
                    onSave(todo.copy(title = title, notes = notes, reminderAt = reminder, repeatRule = repeat))
                }, enabled = title.isNotBlank()) { Text("Save") }
            }
        }
    }
}
