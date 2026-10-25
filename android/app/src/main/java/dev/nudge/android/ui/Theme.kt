package dev.nudge.android.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

val Orange = Color(0xFFF0731F)
val Green = Color(0xFF34C759)

@Composable
fun NudgeTheme(dark: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    val scheme = if (dark) darkColorScheme(
        primary = Orange,
        onPrimary = Color.White,
        secondary = Color(0xFFF59E0B),
        surface = Color(0xFF151517),
        background = Color(0xFF0E0E10),
        surfaceVariant = Color(0xFF232326),
    ) else lightColorScheme(
        primary = Orange,
        onPrimary = Color.White,
        secondary = Color(0xFFD97706),
        surface = Color(0xFFFCFCFD),
        background = Color(0xFFF4F4F6),
        surfaceVariant = Color(0xFFEDEDF0),
    )
    MaterialTheme(colorScheme = scheme, content = content)
}
