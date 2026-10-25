package dev.nudge.android.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.selection.selectable
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import dev.nudge.android.Graph
import dev.nudge.android.data.Dates
import dev.nudge.android.data.RepeatRule
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset

/**
 * Bell button opening a menu of presets + custom date/time + repeat + remove.
 * [reminder] is epoch ms or null.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReminderPicker(
    reminder: Long?,
    onReminderChange: (Long?) -> Unit,
    repeat: RepeatRule = RepeatRule.NONE,
    onRepeatChange: ((RepeatRule) -> Unit)? = null,
    tint: androidx.compose.ui.graphics.Color = if (reminder != null) Orange else MaterialTheme.colorScheme.onSurfaceVariant,
) {
    var menuOpen by remember { mutableStateOf(false) }
    var dateOpen by remember { mutableStateOf(false) }
    var timeOpen by remember { mutableStateOf(false) }
    var repeatOpen by remember { mutableStateOf(false) }
    var pickedDate by remember { mutableStateOf<LocalDate?>(null) }
    val settings = Graph.settings.value

    IconButton(onClick = { menuOpen = true }) {
        Icon(
            if (reminder != null) Icons.Filled.Notifications else Icons.Outlined.Notifications,
            contentDescription = "Reminder", tint = tint,
        )
    }

    DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
        fun pick(ms: Long) { onReminderChange(ms); menuOpen = false }
        val now = System.currentTimeMillis()
        DropdownMenuItem(text = { Text("In 10 minutes") }, onClick = { pick(now + 10 * 60_000) })
        DropdownMenuItem(text = { Text("In 30 minutes") }, onClick = { pick(now + 30 * 60_000) })
        DropdownMenuItem(text = { Text("In 1 hour") }, onClick = { pick(now + 60 * 60_000) })
        DropdownMenuItem(text = { Text("In 3 hours") }, onClick = { pick(now + 3 * 60 * 60_000) })
        HorizontalDivider()
        DropdownMenuItem(text = { Text("This evening · ${Dates.hourLabel(settings.eveningHour)}") },
            onClick = { pick(Dates.nextOccurrence(settings.eveningHour)) })
        DropdownMenuItem(text = { Text("Tomorrow · ${Dates.hourLabel(settings.morningHour)}") },
            onClick = { pick(Dates.tomorrow(settings.morningHour)) })
        HorizontalDivider()
        DropdownMenuItem(text = { Text("Pick date & time…") }, onClick = { menuOpen = false; dateOpen = true })
        if (onRepeatChange != null && reminder != null) {
            DropdownMenuItem(text = { Text("Repeat: ${repeat.label}") }, onClick = { menuOpen = false; repeatOpen = true })
        }
        if (reminder != null) {
            HorizontalDivider()
            DropdownMenuItem(
                text = { Text("Remove reminder", color = MaterialTheme.colorScheme.error) },
                onClick = { onReminderChange(null); onRepeatChange?.invoke(RepeatRule.NONE); menuOpen = false },
            )
        }
    }

    if (dateOpen) {
        val initial = reminder ?: Dates.roundedUpToFiveMinutes()
        val state = rememberDatePickerState(
            initialSelectedDateMillis = Instant.ofEpochMilli(initial).atZone(ZoneId.systemDefault())
                .toLocalDate().atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli(),
        )
        DatePickerDialog(
            onDismissRequest = { dateOpen = false },
            confirmButton = {
                TextButton(onClick = {
                    val ms = state.selectedDateMillis
                    if (ms != null) {
                        pickedDate = Instant.ofEpochMilli(ms).atZone(ZoneOffset.UTC).toLocalDate()
                        dateOpen = false
                        timeOpen = true
                    }
                }) { Text("Next") }
            },
            dismissButton = { TextButton(onClick = { dateOpen = false }) { Text("Cancel") } },
        ) { DatePicker(state = state) }
    }

    if (timeOpen) {
        val initial = Instant.ofEpochMilli(reminder ?: Dates.roundedUpToFiveMinutes()).atZone(ZoneId.systemDefault())
        val state = rememberTimePickerState(initialHour = initial.hour, initialMinute = initial.minute)
        AlertDialog(
            onDismissRequest = { timeOpen = false },
            title = { Text("Remind me at") },
            text = { TimePicker(state = state) },
            confirmButton = {
                TextButton(onClick = {
                    val date = pickedDate ?: LocalDate.now()
                    onReminderChange(Dates.combine(date, state.hour, state.minute))
                    timeOpen = false
                }) { Text("Set reminder") }
            },
            dismissButton = { TextButton(onClick = { timeOpen = false }) { Text("Cancel") } },
        )
    }

    if (repeatOpen && onRepeatChange != null) {
        AlertDialog(
            onDismissRequest = { repeatOpen = false },
            title = { Text("Repeat") },
            text = {
                Column {
                    RepeatRule.entries.forEach { rule ->
                        Row(
                            Modifier
                                .fillMaxWidth()
                                .selectable(selected = rule == repeat, onClick = { onRepeatChange(rule); repeatOpen = false })
                                .padding(vertical = 8.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            RadioButton(selected = rule == repeat, onClick = null)
                            Text(rule.label, modifier = Modifier.padding(start = 8.dp))
                        }
                    }
                }
            },
            confirmButton = { TextButton(onClick = { repeatOpen = false }) { Text("Done") } },
        )
    }
}
