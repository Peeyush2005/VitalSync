package com.example.vitalsync.ui.theme

import androidx.compose.runtime.Composable
import androidx.wear.compose.material.Colors
import androidx.wear.compose.material.MaterialTheme

/**
 * Wear Compose theme for VitalSync watch app.
 *
 * Uses [androidx.wear.compose.material.MaterialTheme] optimized for round AMOLED displays.
 */
private val VitalSyncWearColors = Colors(
    primary = VitalTeal,
    primaryVariant = VitalTealDark,
    secondary = StepEmerald,
    secondaryVariant = VitalTealLight,
    error = PulseCrimson,
    onPrimary = OledBlack,
    onSecondary = OledBlack,
    onError = OledBlack,
    background = OledBlack,
    onBackground = TextPrimary,
    surface = SurfaceDark,
    onSurface = TextPrimary,
    onSurfaceVariant = TextSecondary,
)

@Composable
fun VitalSyncTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colors = VitalSyncWearColors,
        content = content,
    )
}