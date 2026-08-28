package com.example.vitalsync

import android.Manifest
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
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
 * 100% Real Physical Hardware Optical Sensor Stream:
 * - Reads direct PPG optical LED heart rate hardware sensor via [SensorManager] ([Sensor.TYPE_HEART_RATE])
 *   and Samsung Health Sensor SDK ([HealthTrackingService]).
 * - Zero simulated data.
 * - Streams live biometric measurements to the phone over Google Play Services Wearable.
 */
class MainActivity : ComponentActivity() {

    companion object {
        private const val TAG = "VitalSyncWatch"
        private const val CONNECTION_PATH = "/vitalsync/connection"
        private const val HEARTRATE_PATH = "/vitalsync/heartrate"
        private const val HEALTH_READ_HEART_RATE = "android.permission.health.READ_HEART_RATE"
        private const val HEARTBEAT_PING_INTERVAL_MS = 10_000L
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var isStreamingActive = false

    // Hardware Sensors
    private var sensorManager: SensorManager? = null
    private var androidHeartRateSensor: Sensor? = null
    private var isAndroidSensorListening = false

    // Samsung SDK
    private var healthTrackingService: HealthTrackingService? = null
    private var healthTracker: HealthTracker? = null

    // UI Listeners
    private var onHeartRateListener: ((Int) -> Unit)? = null
    private var onStatusListener: ((Boolean, String) -> Unit)? = null

    private val requiredPermissions: Array<String>
        get() {
            val list = mutableListOf(
                Manifest.permission.BODY_SENSORS,
                Manifest.permission.BODY_SENSORS_BACKGROUND,
            )
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                list.add(HEALTH_READ_HEART_RATE)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                list.add(Manifest.permission.ACTIVITY_RECOGNITION)
            }
            return list.toTypedArray()
        }

    private val androidSensorEventListener = object : SensorEventListener {
        override fun onSensorChanged(event: SensorEvent?) {
            if (event == null || event.sensor.type != Sensor.TYPE_HEART_RATE) return
            val bpm = event.values.firstOrNull()?.toInt() ?: 0
            val accuracy = event.accuracy
            Log.d(TAG, "Hardware PPG optical sensor event: bpm=$bpm accuracy=$accuracy")

            if (bpm > 0) {
                mainHandler.post {
                    onHeartRateListener?.invoke(bpm)
                    onStatusListener?.invoke(true, "Live: $bpm BPM")
                }
                sendRealHeartRateMessage(bpm = bpm, timestamp = System.currentTimeMillis())
            } else {
                mainHandler.post {
                    onStatusListener?.invoke(true, "Place watch on wrist…")
                }
            }
        }

        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
            Log.d(TAG, "Hardware sensor accuracy: $accuracy")
        }
    }

    private val connectionListener = object : ConnectionListener {
        override fun onConnectionSuccess() {
            Log.d(TAG, "Samsung Health Tracking Service connected")
            startSamsungHeartRateTracker()
        }

        override fun onConnectionEnded() {
            Log.d(TAG, "Samsung Health Tracking Service ended")
        }

        override fun onConnectionFailed(e: HealthTrackerException) {
            Log.w(TAG, "Samsung Health Tracking connection failed: ${e.message} — using Wear OS PPG sensor", e)
            startHardwareSensor()
        }
    }

    private val trackerEventListener = object : HealthTracker.TrackerEventListener {
        override fun onDataReceived(dataPoints: List<DataPoint>) {
            for (dataPoint in dataPoints) {
                val hr = dataPoint.getValue(ValueKey.HeartRateSet.HEART_RATE)
                val status = dataPoint.getValue(ValueKey.HeartRateSet.HEART_RATE_STATUS)
                Log.d(TAG, "Samsung HR dataPoint: hr=$hr status=$status timestamp=${dataPoint.timestamp}")

                if (hr != null && hr > 0) {
                    mainHandler.post {
                        onHeartRateListener?.invoke(hr)
                        onStatusListener?.invoke(true, "Live: $hr BPM")
                    }
                    sendRealHeartRateMessage(bpm = hr, timestamp = dataPoint.timestamp)
                }
            }
        }

        override fun onFlushCompleted() {}

        override fun onError(error: HealthTracker.TrackerError) {
            Log.w(TAG, "Samsung Tracker error: $error — fallback to Wear OS PPG sensor")
            startHardwareSensor()
        }
    }

    private val heartbeatPingRunnable = object : Runnable {
        override fun run() {
            if (!isStreamingActive) return
            sendHeartbeatPing()
            mainHandler.postDelayed(this, HEARTBEAT_PING_INTERVAL_MS)
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
                    hasPermission = hasAllPermissions(),
                    onRequestPermission = { onGranted -> requestAllPermissions(onGranted) },
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

    private fun hasAllPermissions(): Boolean =
        ContextCompat.checkSelfPermission(this, Manifest.permission.BODY_SENSORS) ==
            PackageManager.PERMISSION_GRANTED

    private var permissionCallback: ((Boolean) -> Unit)? = null
    private val requestPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions(),
    ) { results ->
        val allGranted = results.values.all { it }
        permissionCallback?.invoke(allGranted)
        permissionCallback = null
    }

    private fun requestAllPermissions(onResult: (Boolean) -> Unit) {
        if (hasAllPermissions()) {
            onResult(true)
            return
        }
        permissionCallback = onResult
        requestPermissionLauncher.launch(requiredPermissions)
    }

    private fun toggleStreaming(start: Boolean) {
        if (start) {
            if (!hasAllPermissions()) {
                requestAllPermissions { granted ->
                    if (granted) startStreaming()
                    else onStatusListener?.invoke(false, "Permissions required")
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
        onStatusListener?.invoke(true, "Sensor active — reading…")

        // Start heartbeat ping so phone is aware of connection
        mainHandler.removeCallbacks(heartbeatPingRunnable)
        mainHandler.post(heartbeatPingRunnable)

        // 1. Activate standard hardware PPG optical sensor
        startHardwareSensor()

        // 2. Also try Samsung SDK
        try {
            healthTrackingService = HealthTrackingService(connectionListener, applicationContext)
            healthTrackingService?.connectService()
        } catch (t: Throwable) {
            Log.w(TAG, "Samsung SDK not initialized: ${t.message}")
        }
    }

    private fun startSamsungHeartRateTracker() {
        try {
            healthTracker = healthTrackingService?.getHealthTracker(HealthTrackerType.HEART_RATE_CONTINUOUS)
                ?: healthTrackingService?.getHealthTracker(HealthTrackerType.HEART_RATE)

            healthTracker?.setEventListener(trackerEventListener)
            Log.d(TAG, "Samsung HeartTracker event listener attached")
        } catch (t: Throwable) {
            Log.e(TAG, "Failed to start Samsung HeartTracker", t)
        }
    }

    private fun startHardwareSensor() {
        if (isAndroidSensorListening) return
        try {
            val sm = sensorManager ?: (getSystemService(SENSOR_SERVICE) as SensorManager)
            val hrSensor = androidHeartRateSensor ?: sm.getDefaultSensor(Sensor.TYPE_HEART_RATE)
            if (hrSensor != null) {
                val registered = sm.registerListener(
                    androidSensorEventListener,
                    hrSensor,
                    SensorManager.SENSOR_DELAY_FASTEST,
                )
                isAndroidSensorListening = registered
                Log.d(TAG, "Optical PPG Sensor registered: $registered")
            } else {
                Log.w(TAG, "No heart rate hardware sensor found")
            }
        } catch (t: Throwable) {
            Log.e(TAG, "Failed to register SensorManager listener", t)
        }
    }

    private fun stopStreaming() {
        isStreamingActive = false
        mainHandler.removeCallbacks(heartbeatPingRunnable)

        try {
            healthTracker?.unsetEventListener()
            healthTracker = null
            healthTrackingService?.disconnectService()
            healthTrackingService = null
        } catch (t: Throwable) {
            Log.w(TAG, "Error disconnecting Samsung tracking service", t)
        }

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

    private fun sendRealHeartRateMessage(bpm: Int, timestamp: Long) {
        Wearable.getNodeClient(this).connectedNodes
            .addOnSuccessListener { nodes ->
                if (nodes.isEmpty()) return@addOnSuccessListener
                val payload = JSONObject().apply {
                    put("type", "heart_rate")
                    put("value", bpm)
                    put("unit", "bpm")
                    put("timestamp", timestamp)
                }.toString().toByteArray(Charsets.UTF_8)

                val messageClient: MessageClient = Wearable.getMessageClient(this)
                nodes.forEach { node ->
                    messageClient.sendMessage(node.id, HEARTRATE_PATH, payload)
                        .addOnSuccessListener {
                            Log.d(TAG, "Live BPM $bpm sent to ${node.displayName}")
                        }
                }
            }
    }

    private fun sendHeartbeatPing() {
        Wearable.getNodeClient(this).connectedNodes
            .addOnSuccessListener { nodes ->
                if (nodes.isEmpty()) return@addOnSuccessListener
                val payload = JSONObject().apply {
                    put("type", "ping")
                    put("value", JSONObject.NULL)
                    put("unit", "bpm")
                    put("timestamp", System.currentTimeMillis())
                }.toString().toByteArray(Charsets.UTF_8)

                val messageClient: MessageClient = Wearable.getMessageClient(this)
                nodes.forEach { node ->
                    messageClient.sendMessage(node.id, HEARTRATE_PATH, payload)
                }
            }
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
                        onResult("Connected to $nodeNames ✓")
                    }.addOnFailureListener { e ->
                        onResult("Failed: ${e.message?.take(15)}")
                    }
                }
            }
            .addOnFailureListener { e -> onResult("Error: ${e.message?.take(15)}") }
    }
}

/**
 * Main watch UI — round Wear OS display with live physical PPG heart rate.
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
                        tint = if (isStreaming && heartRate > 0) MaterialTheme.colors.primary else MaterialTheme.colors.onSurfaceVariant,
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
                            text = if (isStreaming) (if (heartRate > 0) "❤️ $heartRate BPM (Live)" else statusText) else "Optical PPG sensor",
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
                    label = { Text("Sensor permissions", style = MaterialTheme.typography.button) },
                    secondaryLabel = {
                        Text(
                            text = if (permissionGranted) "Granted ✓" else "Tap to grant",
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
                        pingStatus = "Pinging…"
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
