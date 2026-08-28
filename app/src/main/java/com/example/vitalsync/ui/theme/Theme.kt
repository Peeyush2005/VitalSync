package com.example.vitalsync.ui.theme

import androidx.compose.runtime.Composable
import androidx.wear.compose.material.Colors
import androidx.wear.compose.material.MaterialTheme

/**
 * Wear Compose theme for VitalSync watch app.
 *
 * Uses [androidx.wear.compose.material.MaterialTheme] (not phone Material3)
 * so all components (Chip, ScalingLazyColumn, etc.) render correctly on
 * round and small Wear OS displays.
 */
private val VitalSyncWearColors = Colors(
    primary = VitalTeal,
    primaryVariant = VitalTealDark,
    secondary = VitalGreen,
    secondaryVariant = VitalTealLight,
    error = VitalRed,
    onPrimary = VitalWhite,
    onSecondary = VitalBlack,
    onError = VitalBlack,
    background = VitalBlack,
    onBackground = VitalWhite,
    surface = VitalDarkSurface,
    onSurface = VitalWhite,
    onSurfaceVariant = VitalGrey,
)

@Composable
fun VitalSyncTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colors = VitalSyncWearColors,
        content = content,
    )
}