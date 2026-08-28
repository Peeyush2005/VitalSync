package com.example.vitalsync

import android.Manifest
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
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
 * Dual-Engine Live Biometric Tracking:
 * 1. Primary: Samsung Health Sensor SDK ([HealthTrackingService] & [HealthTracker]).
 * 2. Fallback: Android Wear OS [SensorManager] ([Sensor.TYPE_HEART_RATE]).
 * 3. Streams live standardized JSON measurements over Google Play Services Wearable Data Layer.
 * 4. Built with Wear Compose for round AMOLED displays.
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

    // Android Platform SensorManager objects
    private var sensorManager: SensorManager? = null
    private var androidHeartRateSensor: Sensor? = null
    private var isAndroidSensorListening = false

    // UI listeners
    private var onHeartRateListener: ((Int) -> Unit)? = null
    private var onStatusListener: ((Boolean, String) -> Unit)? = null

    private val androidSensorEventListener = object : SensorEventListener {
        override fun onSensorChanged(event: SensorEvent?) {
            if (event == null || event.sensor.type != Sensor.TYPE_HEART_RATE) return
            val bpm = event.values.firstOrNull()?.toInt() ?: 0
            val accuracy = event.accuracy
            Log.d(TAG, "Wear OS SensorManager HR: $bpm accuracy=$accuracy")

            if (bpm > 0) {
                mainHandler.post {
                    onHeartRateListener?.invoke(bpm)
                    onStatusListener?.invoke(true, "Live: $bpm BPM")
                }
                sendHeartRateMessage(bpm = bpm, timestamp = System.currentTimeMillis())
            }
        }

        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
    }

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
            Log.w(TAG, "Samsung Health Tracking Service connection failed: ${e.message} — falling back to Wear OS sensor", e)
            startAndroidHeartRateSensor()
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
            Log.w(TAG, "Samsung Tracker error: $error — switching to Wear OS heart-rate sensor")
            mainHandler.post {
                onStatusListener?.invoke(isStreamingActive, "Wear OS Sensor Active")
            }
            startAndroidHeartRateSensor()
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
        sensorManager = getSystemService(SENSOR_SERVICE) as SensorManager
        androidHeartRateSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_HEART_RATE)

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
        val sm = getSystemService(SENSOR_SERVICE) as SensorManager
        return sm.getDefaultSensor(Sensor.TYPE_HEART_RATE) != null
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

        // Start fallback heartbeat ping so phone knows watch is active immediately
        startFallbackPingLoop()

        try {
            healthTrackingService = HealthTrackingService(connectionListener, applicationContext)
            healthTrackingService?.connectService()
        } catch (t: Throwable) {
            Log.w(TAG, "Could not initialize Samsung HealthTrackingService, falling back to Wear OS sensor", t)
            startAndroidHeartRateSensor()
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
                Log.w(TAG, "No heart tracker available from Samsung service, starting Wear OS sensor")
                startAndroidHeartRateSensor()
            }
        } catch (t: Throwable) {
            Log.e(TAG, "Failed to start Samsung HeartTracker, starting Wear OS sensor", t)
            startAndroidHeartRateSensor()
        }
    }

    private fun startAndroidHeartRateSensor() {
        if (isAndroidSensorListening) return
        try {
            val sm = sensorManager ?: (getSystemService(SENSOR_SERVICE) as SensorManager)
            val hrSensor = androidHeartRateSensor ?: sm.getDefaultSensor(Sensor.TYPE_HEART_RATE)
            if (hrSensor != null) {
                sm.registerListener(
                    androidSensorEventListener,
                    hrSensor,
                    SensorManager.SENSOR_DELAY_NORMAL,
                )
                isAndroidSensorListening = true
                mainHandler.post {
                    onStatusListener?.invoke(true, "Sensor: Reading…")
                }
                Log.d(TAG, "Registered Android SensorManager heart rate listener")
            } else {
                Log.w(TAG, "No Android heart rate sensor available, using ping stream")
                mainHandler.post {
                    onStatusListener?.invoke(true, "Fallback streaming")
                }
            }
        } catch (t: Throwable) {
            Log.e(TAG, "Failed to register Android SensorManager listener", t)
        }
    }

    private fun startFallbackPingLoop() {
        mainHandler.removeCallbacks(fallbackPingRunnable)
        mainHandler.post(fallbackPingRunnable)
    }

    private fun stopStreaming() {
        isStreamingActive = false
        mainHandler.removeCallbacks(fallbackPingRunnable)

        // Stop Samsung Health tracker
        try {
            healthTracker?.unsetEventListener()
            healthTracker = null
            healthTrackingService?.disconnectService()
            healthTrackingService = null
        } catch (t: Throwable) {
            Log.w(TAG, "Error disconnecting Samsung tracking service", t)
        }

        // Stop Android SensorManager
        try {
            if (isAndroidSensorListening) {
                sensorManager?.unregisterListener(androidSensorEventListener)
                isAndroidSensorListening = false
            }
        } catch (t: Throwable) {
            Log.w(TAG, "Error unregistering Android SensorManager listener", t)
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
                            Log.d(TAG, "Heart rate sent to node ${node.displayName} (${bpm ?: "ping"})")
                        }
                        .addOnFailureListener { e ->
                            Log.w(TAG, "Failed to send to node ${node.displayName}: ${e.message}")
                        }
                }
            }
            .addOnFailureListener { e -> Log.w(TAG, "NodeClient error: ${e.message}") }
    }

    private fun sendConnectionPing(onResult: (String) -> Unit) {
        Wearable.getNodeClient(this).connectedNodes
            .addOnSuccessListener { nodes ->
                if (nodes.isEmpty()) {
                    onResult("No phone paired")
                    return@addOnSuccessListener
                }
                val nodeNames = nodes.joinToString { it.displayName }
                val messageClient: MessageClient = Wearable.getMessageClient(this)
                nodes.forEach { node ->
                    messageClient.sendMessage(
                        node.id,
                        CONNECTION_PATH,
                        "connected".toByteArray(Charsets.UTF_8),
                    ).addOnSuccessListener {
                        onResult("Sent to $nodeNames ✓")
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
    var heartRate by remember { mutableIntStateOf(0) }
    var isStreaming by remember { mutableStateOf(false) }
    var statusText by remember { mutableStateOf(if (hasHeartRateSensor) "Sensor ready" else "No sensor") }
    var pingStatus by remember { mutableStateOf("Not sent") }
    var permissionGranted by remember { mutableStateOf(hasPermission) }

    DisposableEffect(Unit) {
        onRegisterHeartRateListener { hr ->
            heartRate = hr
        }
        onRegisterStatusListener { streaming, status ->
            isStreaming = streaming
            statusText = status
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
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 16.dp),
            state = listState,
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            item {
                Spacer(modifier = Modifier.height(20.dp))
                Text(
                    text = "VitalSync",
                    style = MaterialTheme.typography.title1,
                    color = MaterialTheme.colors.primary,
                    textAlign = TextAlign.Center,
                )
            }

            item {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.Center,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Icon(
                        imageVector = if (isStreaming && heartRate > 0) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder,
                        contentDescription = null,
                        tint = if (isStreaming) MaterialTheme.colors.primary else MaterialTheme.colors.onSurfaceVariant,
                        modifier = Modifier.size(16.dp),
                    )
                    Text(
                        text = if (heartRate > 0) " $heartRate BPM" else " $statusText",
                        style = MaterialTheme.typography.body2,
                        color = if (heartRate > 0) MaterialTheme.colors.primary else MaterialTheme.colors.onSurfaceVariant,
                    )
                }
            }

            item {
                Chip(
                    onClick = {
                        if (!permissionGranted) {
                            onRequestPermission { granted ->
                                permissionGranted = granted
                                if (granted) {
                                    isStreaming = !isStreaming
                                    onToggleStreaming(isStreaming)
                                }
                            }
                        } else {
                            isStreaming = !isStreaming
                            onToggleStreaming(isStreaming)
                        }
                    },
                    label = {
                        Text(
                            text = if (isStreaming) "Stop tracking" else "Start tracking",
                            style = MaterialTheme.typography.button,
                        )
                    },
                    secondaryLabel = {
                        Text(
                            text = if (isStreaming) (if (heartRate > 0) "❤️ $heartRate BPM" else statusText) else "Tap to start",
                            style = MaterialTheme.typography.caption2,
                        )
                    },
                    icon = {
                        Icon(
                            imageVector = if (isStreaming) Icons.Filled.Check else Icons.Filled.PlayArrow,
                            contentDescription = null,
                        )
                    },
                    colors = if (isStreaming) {
                        ChipDefaults.primaryChipColors()
                    } else {
                        ChipDefaults.secondaryChipColors()
                    },
                    modifier = Modifier.fillMaxWidth(),
                )
            }

            item {
                Chip(
                    onClick = {
                        if (!permissionGranted) {
                            onRequestPermission { granted ->
                                permissionGranted = granted
                            }
                        }
                    },
                    label = { Text("Body sensors", style = MaterialTheme.typography.button) },
                    secondaryLabel = {
                        Text(
                            text = if (permissionGranted) "Granted" else "Tap to grant",
                            style = MaterialTheme.typography.caption2,
                        )
                    },
                    icon = {
                        Icon(
                            imageVector = if (permissionGranted) Icons.Filled.Check else Icons.Filled.Close,
                            contentDescription = null,
                        )
                    },
                    colors = ChipDefaults.secondaryChipColors(),
                    modifier = Modifier.fillMaxWidth(),
                )
            }

            item {
                Chip(
                    onClick = {
                        pingStatus = "Sending…"
                        onSendPing { result -> pingStatus = result }
                    },
                    label = { Text("Ping phone", style = MaterialTheme.typography.button) },
                    secondaryLabel = { Text(pingStatus, style = MaterialTheme.typography.caption2) },
                    icon = {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.Send,
                            contentDescription = null,
                        )
                    },
                    colors = ChipDefaults.secondaryChipColors(),
                    modifier = Modifier.fillMaxWidth(),
                )
            }

            item {
                Spacer(modifier = Modifier.height(20.dp))
            }
        }
    }
}
