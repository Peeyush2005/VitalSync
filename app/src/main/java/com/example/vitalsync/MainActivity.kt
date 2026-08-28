package com.example.vitalsync

import android.Manifest
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material.Chip
import androidx.wear.compose.material.ChipDefaults
import androidx.wear.compose.material.Icon
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.PositionIndicator
import androidx.wear.compose.material.Scaffold
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.TimeText
import androidx.wear.compose.material.Vignette
import androidx.wear.compose.material.VignettePosition
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.automirrored.filled.Send
import com.example.vitalsync.ui.theme.VitalSyncTheme
import com.google.android.gms.wearable.MessageClient
import com.google.android.gms.wearable.Wearable
import com.samsung.android.service.health.tracking.ConnectionListener
import com.samsung.android.service.health.tracking.HealthTracker
import com.samsung.android.service.health.tracking.HealthTrackerException
import com.samsung.android.service.health.tracking.HealthTrackingService
import com.samsung.android.service.health.tracking.data.DataPoint
import com.samsung.android.service.health.tracking.data.HealthTrackerType
import com.samsung.android.service.health.tracking.data.ValueKey
import org.json.JSONObject

/**
 * VitalSync Wear OS watch app for Galaxy Watch4.
 *
 * Real Samsung Health Sensor SDK Integration:
 * - Uses [HealthTrackingService] and [HealthTracker] for real-time PPG/heart-rate.
 * - Streams live BPM readings over Wear OS Data Layer to paired phone.
 * - Fallback ping loop if SDK is unavailable (e.g. emulator).
 * - Built with Wear Compose for round AMOLED displays.
 */
class MainActivity : ComponentActivity() {

    companion object {
        private const val TAG = "VitalSyncWatch"
        private const val CONNECTION_PATH = "/vitalsync/connection"
        private const val HEARTRATE_PATH = "/vitalsync/heartrate"
        private const val FALLBACK_PING_INTERVAL_MS = 10_000L
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var isStreamingActive = false

    // Samsung Health Sensor SDK objects
    private var healthTrackingService: HealthTrackingService? = null
    private var healthTracker: HealthTracker? = null

    // UI listeners
    private var onHeartRateListener: ((Int) -> Unit)? = null
    private var onStatusListener: ((Boolean, String) -> Unit)? = null

    private val connectionListener = object : ConnectionListener {
        override fun onConnectionSuccess() {
            Log.d(TAG, "Samsung Health Tracking Service connected successfully")
            onStatusListener?.invoke(true, "Samsung Sensor Active")
            startHeartRateTracker()
        }

        override fun onConnectionEnded() {
            Log.d(TAG, "Samsung Health Tracking Service connection ended")
            onStatusListener?.invoke(false, "Sensor disconnected")
        }

        override fun onConnectionFailed(e: HealthTrackerException) {
            Log.w(TAG, "Samsung Health Tracking Service connection failed: ${e.message}", e)
            onStatusListener?.invoke(true, "Using fallback stream")
            // Fall back to periodic ping if Samsung service is unavailable
            startFallbackPingLoop()
        }
    }

    private val trackerEventListener = object : HealthTracker.TrackerEventListener {
        override fun onDataReceived(dataPoints: List<DataPoint>) {
            for (dataPoint in dataPoints) {
                val hr = dataPoint.getValue(ValueKey.HeartRateSet.HEART_RATE)
                val status = dataPoint.getValue(ValueKey.HeartRateSet.HEART_RATE_STATUS)
                Log.d(TAG, "Samsung HR data: hr=$hr status=$status timestamp=${dataPoint.timestamp}")

                if (hr != null && hr > 0) {
                    mainHandler.post {
                        onHeartRateListener?.invoke(hr)
                        onStatusListener?.invoke(true, "Live: $hr BPM")
                    }
                    sendHeartRateMessage(bpm = hr, timestamp = dataPoint.timestamp)
                }
            }
        }

        override fun onFlushCompleted() {
            Log.d(TAG, "Tracker flush completed")
        }

        override fun onError(error: HealthTracker.TrackerError) {
            Log.e(TAG, "Tracker error: $error")
            mainHandler.post {
                onStatusListener?.invoke(isStreamingActive, "Sensor error: $error")
            }
        }
    }

    private val fallbackPingRunnable = object : Runnable {
        override fun run() {
            if (!isStreamingActive) return
            sendHeartRateMessage(bpm = null, timestamp = System.currentTimeMillis())
            mainHandler.postDelayed(this, FALLBACK_PING_INTERVAL_MS)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            VitalSyncTheme {
                WatchApp(
                    hasHeartRateSensor = hasHeartRateSensor(),
                    hasPermission = hasBodySensorsPermission(),
                    onRequestPermission = { onGranted -> requestBodySensorsPermission(onGranted) },
                    onSendPing = { onResult -> sendConnectionPing(onResult) },
                    onToggleStreaming = { start -> toggleStreaming(start) },
                    onRegisterHeartRateListener = { listener -> onHeartRateListener = listener },
                    onRegisterStatusListener = { listener -> onStatusListener = listener },
                )
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        stopStreaming()
    }

    private fun hasHeartRateSensor(): Boolean {
        val sensorManager = getSystemService(SENSOR_SERVICE) as SensorManager
        return sensorManager.getDefaultSensor(Sensor.TYPE_HEART_RATE) != null
    }

    private fun hasBodySensorsPermission(): Boolean =
        ContextCompat.checkSelfPermission(this, Manifest.permission.BODY_SENSORS) ==
            PackageManager.PERMISSION_GRANTED

    private lateinit var permissionCallback: (Boolean) -> Unit
    private val requestPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted -> permissionCallback(granted) }

    private fun requestBodySensorsPermission(onResult: (Boolean) -> Unit) {
        if (hasBodySensorsPermission()) {
            onResult(true)
            return
        }
        permissionCallback = onResult
        requestPermissionLauncher.launch(Manifest.permission.BODY_SENSORS)
    }

    private fun toggleStreaming(start: Boolean) {
        if (start) {
            if (!hasBodySensorsPermission()) {
                requestBodySensorsPermission { granted ->
                    if (granted) startStreaming()
                    else onStatusListener?.invoke(false, "Permission required")
                }
            } else {
                startStreaming()
            }
        } else {
            stopStreaming()
        }
    }

    private fun startStreaming() {
        isStreamingActive = true
        onStatusListener?.invoke(true, "Connecting to sensor…")

        try {
            healthTrackingService = HealthTrackingService(connectionListener, applicationContext)
            healthTrackingService?.connectService()
        } catch (t: Throwable) {
            Log.w(TAG, "Could not initialize Samsung HealthTrackingService", t)
            onStatusListener?.invoke(true, "Fallback streaming")
            startFallbackPingLoop()
        }
    }

    private fun startHeartRateTracker() {
        try {
            healthTracker = healthTrackingService?.getHealthTracker(HealthTrackerType.HEART_RATE_CONTINUOUS)
                ?: healthTrackingService?.getHealthTracker(HealthTrackerType.HEART_RATE)

            if (healthTracker != null) {
                healthTracker?.setEventListener(trackerEventListener)
                Log.d(TAG, "Samsung HeartTracker event listener attached")
            } else {
                Log.w(TAG, "No heart tracker available from Samsung service, starting fallback")
                startFallbackPingLoop()
            }
        } catch (t: Throwable) {
            Log.e(TAG, "Failed to start Samsung HeartTracker", t)
            startFallbackPingLoop()
        }
    }

    private fun startFallbackPingLoop() {
        mainHandler.removeCallbacks(fallbackPingRunnable)
        mainHandler.post(fallbackPingRunnable)
    }

    private fun stopStreaming() {
        isStreamingActive = false
        mainHandler.removeCallbacks(fallbackPingRunnable)

        try {
            healthTracker?.unsetEventListener()
            healthTracker = null
            healthTrackingService?.disconnectService()
            healthTrackingService = null
        } catch (t: Throwable) {
            Log.w(TAG, "Error disconnecting Samsung tracking service", t)
        }

        onStatusListener?.invoke(false, "Stopped")
    }

    private fun sendHeartRateMessage(bpm: Int?, timestamp: Long) {
        Wearable.getNodeClient(this).connectedNodes
            .addOnSuccessListener { nodes ->
                if (nodes.isEmpty()) {
                    Log.d(TAG, "No connected phone node found")
                    return@addOnSuccessListener
                }
                val payload = JSONObject().apply {
                    put("type", if (bpm != null) "heart_rate" else "ping")
                    if (bpm != null) put("value", bpm) else put("value", JSONObject.NULL)
                    put("unit", "bpm")
                    put("timestamp", timestamp)
                }.toString().toByteArray(Charsets.UTF_8)

                val messageClient: MessageClient = Wearable.getMessageClient(this)
                nodes.forEach { node ->
                    messageClient.sendMessage(node.id, HEARTRATE_PATH, payload)
                        .addOnSuccessListener {
                            Log.d(TAG, "Heart rate sent to phone (${bpm ?: "ping"})")
                        }
                        .addOnFailureListener { e ->
                            Log.w(TAG, "Failed to send to phone: ${e.message}")
                        }
                }
            }
            .addOnFailureListener { e -> Log.w(TAG, "NodeClient error: ${e.message}") }
    }

    private fun sendConnectionPing(onResult: (String) -> Unit) {
        Wearable.getNodeClient(this).connectedNodes
            .addOnSuccessListener { nodes ->
                if (nodes.isEmpty()) {
                    onResult("No phone nearby")
                    return@addOnSuccessListener
                }
                val messageClient: MessageClient = Wearable.getMessageClient(this)
                nodes.forEach { node ->
                    messageClient.sendMessage(
                        node.id,
                        CONNECTION_PATH,
                        "connected".toByteArray(Charsets.UTF_8),
                    ).addOnSuccessListener {
                        onResult("Sent ✓")
                    }.addOnFailureListener { e ->
                        onResult("Failed: ${e.message?.take(20)}")
                    }
                }
            }
            .addOnFailureListener { e -> onResult("Error: ${e.message?.take(20)}") }
    }
}

/**
 * Main watch UI — round Wear OS display with live heart rate.
 */
@Composable
fun WatchApp(
    hasHeartRateSensor: Boolean,
    hasPermission: Boolean,
    onRequestPermission: ((Boolean) -> Unit) -> Unit,
    onSendPing: ((String) -> Unit) -> Unit,
    onToggleStreaming: (Boolean) -> Unit,
    onRegisterHeartRateListener: (((Int) -> Unit)?) -> Unit,
    onRegisterStatusListener: (((Boolean, String) -> Unit)?) -> Unit,
) {
    var permissionStatus by remember {
        mutableStateOf(if (hasPermission) "Granted" else "Not granted")
    }
    var pingStatus by remember { mutableStateOf("Not sent") }
    var isStreaming by remember { mutableStateOf(false) }
    var streamStatus by remember { mutableStateOf("Tap to start") }
    var currentBpm by remember { mutableIntStateOf(0) }

    DisposableEffect(Unit) {
        onRegisterHeartRateListener { bpm ->
            currentBpm = bpm
        }
        onRegisterStatusListener { active, status ->
            isStreaming = active
            streamStatus = status
        }
        onDispose {
            onRegisterHeartRateListener(null)
            onRegisterStatusListener(null)
        }
    }

    val listState = rememberScalingLazyListState()

    Scaffold(
        timeText = { TimeText() },
        vignette = { Vignette(vignettePosition = VignettePosition.TopAndBottom) },
        positionIndicator = { PositionIndicator(scalingLazyListState = listState) },
    ) {
        ScalingLazyColumn(
            modifier = Modifier.fillMaxSize(),
            state = listState,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            // Title
            item {
                Text(
                    text = "VitalSync",
                    style = MaterialTheme.typography.title2,
                    color = MaterialTheme.colors.primary,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth(),
                )
            }

            // Live HR display or sensor status
            item {
                if (currentBpm > 0 && isStreaming) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 4.dp),
                        horizontalArrangement = Arrangement.Center,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(
                            imageVector = Icons.Filled.Favorite,
                            contentDescription = "Live Heart Rate",
                            tint = MaterialTheme.colors.error,
                            modifier = Modifier.size(20.dp),
                        )
                        Text(
                            text = " $currentBpm BPM",
                            style = MaterialTheme.typography.title3,
                            color = MaterialTheme.colors.onBackground,
                            modifier = Modifier.padding(start = 4.dp),
                        )
                    }
                } else {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 2.dp),
                        horizontalArrangement = Arrangement.Center,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(
                            imageVector = Icons.Filled.FavoriteBorder,
                            contentDescription = "Heart rate sensor",
                            tint = if (hasHeartRateSensor) MaterialTheme.colors.secondary
                                   else MaterialTheme.colors.error,
                            modifier = Modifier.size(14.dp),
                        )
                        Text(
                            text = if (hasHeartRateSensor) " Samsung SDK ready" else " No HR sensor",
                            style = MaterialTheme.typography.caption2,
                            color = if (hasHeartRateSensor) MaterialTheme.colors.secondary
                                    else MaterialTheme.colors.error,
                            modifier = Modifier.padding(start = 4.dp),
                        )
                    }
                }
            }

            // Samsung Sensor Streaming toggle chip
            item {
                Chip(
                    modifier = Modifier.fillMaxWidth(0.9f),
                    onClick = {
                        val next = !isStreaming
                        isStreaming = next
                        onToggleStreaming(next)
                    },
                    label = {
                        Text(
                            text = if (isStreaming) "Sensor: ACTIVE" else "Start tracking",
                            style = MaterialTheme.typography.caption1,
                            maxLines = 1,
                        )
                    },
                    secondaryLabel = {
                        Text(
                            text = streamStatus,
                            style = MaterialTheme.typography.caption2,
                            maxLines = 1,
                        )
                    },
                    icon = {
                        Icon(
                            imageVector = if (isStreaming) Icons.Filled.Check else Icons.Filled.PlayArrow,
                            contentDescription = null,
                            modifier = Modifier.size(ChipDefaults.IconSize),
                        )
                    },
                    colors = if (isStreaming) {
                        ChipDefaults.primaryChipColors()
                    } else {
                        ChipDefaults.secondaryChipColors()
                    },
                )
            }

            // Permission chip
            item {
                Chip(
                    modifier = Modifier.fillMaxWidth(0.9f),
                    onClick = {
                        onRequestPermission { granted ->
                            permissionStatus = if (granted) "Granted" else "Denied"
                        }
                    },
                    label = {
                        Text(
                            text = "Body sensors",
                            style = MaterialTheme.typography.caption1,
                            maxLines = 1,
                        )
                    },
                    secondaryLabel = {
                        Text(
                            text = permissionStatus,
                            style = MaterialTheme.typography.caption2,
                            maxLines = 1,
                        )
                    },
                    icon = {
                        Icon(
                            imageVector = if (permissionStatus == "Granted")
                                Icons.Filled.Check else Icons.Filled.Close,
                            contentDescription = null,
                            modifier = Modifier.size(ChipDefaults.IconSize),
                        )
                    },
                    colors = ChipDefaults.secondaryChipColors(),
                )
            }

            // One-off Ping chip
            item {
                Chip(
                    modifier = Modifier.fillMaxWidth(0.9f),
                    onClick = {
                        pingStatus = "Sending…"
                        onSendPing { result -> pingStatus = result }
                    },
                    label = {
                        Text(
                            text = "Ping phone",
                            style = MaterialTheme.typography.caption1,
                            maxLines = 1,
                        )
                    },
                    secondaryLabel = {
                        Text(
                            text = pingStatus,
                            style = MaterialTheme.typography.caption2,
                            maxLines = 1,
                        )
                    },
                    icon = {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.Send,
                            contentDescription = null,
                            modifier = Modifier.size(ChipDefaults.IconSize),
                        )
                    },
                    colors = ChipDefaults.secondaryChipColors(),
                )
            }

            // Clearance spacer for round display
            item {
                Spacer(modifier = Modifier.height(24.dp))
            }
        }
    }
}
