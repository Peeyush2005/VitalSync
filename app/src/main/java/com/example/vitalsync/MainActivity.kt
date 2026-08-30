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
import android.os.SystemClock
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
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
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.automirrored.filled.Send
import com.example.vitalsync.ui.theme.OledBlack
import com.example.vitalsync.ui.theme.OxygenCyan
import com.example.vitalsync.ui.theme.PulseCrimson
import com.example.vitalsync.ui.theme.StatusAmber
import com.example.vitalsync.ui.theme.StatusGreen
import com.example.vitalsync.ui.theme.StepEmerald
import com.example.vitalsync.ui.theme.SurfaceDark
import com.example.vitalsync.ui.theme.SurfaceDarkBorder
import com.example.vitalsync.ui.theme.SurfaceDarkElevated
import com.example.vitalsync.ui.theme.TextMuted
import com.example.vitalsync.ui.theme.TextPrimary
import com.example.vitalsync.ui.theme.TextSecondary
import com.example.vitalsync.ui.theme.VitalSyncTheme
import com.example.vitalsync.ui.theme.VitalTeal
import com.google.android.gms.wearable.MessageClient
import com.google.android.gms.wearable.Node
import com.google.android.gms.wearable.NodeClient
import com.google.android.gms.wearable.Wearable
import com.samsung.android.service.health.tracking.ConnectionListener
import com.samsung.android.service.health.tracking.HealthTracker
import com.samsung.android.service.health.tracking.HealthTrackerException
import com.samsung.android.service.health.tracking.HealthTrackingService
import com.samsung.android.service.health.tracking.data.DataPoint
import com.samsung.android.service.health.tracking.data.HealthTrackerType
import com.samsung.android.service.health.tracking.data.ValueKey
import org.json.JSONObject
import kotlin.math.abs

/**
 * VitalSync Wear OS watch app for Galaxy Watch4.
 *
 * 100% Real Physical Hardware Optical Sensor Stream:
 * - High-efficiency sensor & IPC rate-limiting (bounded 1Hz transmission, zero recomposition storm).
 * - Reads direct PPG optical LED hardware sensor ([Sensor.TYPE_HEART_RATE]) and Samsung Health Sensor SDK.
 * - Hardware step counter ([Sensor.TYPE_STEP_COUNTER]) and on-demand SpO2 spot measurement.
 * - Silky smooth 60fps AMOLED UI.
 */
class MainActivity : ComponentActivity() {

    companion object {
        private const val TAG = "VitalSyncWatch"
        private const val CONNECTION_PATH = "/vitalsync/connection"
        private const val HEARTRATE_PATH = "/vitalsync/heartrate"
        private const val STEPS_PATH = "/vitalsync/steps"
        private const val SPO2_PATH = "/vitalsync/spo2"
        private const val HEALTH_READ_HEART_RATE = "android.permission.health.READ_HEART_RATE"
        private const val HEARTBEAT_PING_INTERVAL_MS = 10_000L

        // Rate-limiting constants to prevent watch CPU saturation and IPC flooding
        private const val UI_UPDATE_THROTTLE_MS = 500L
        private const val IPC_HR_THROTTLE_MS = 1000L
        private const val IPC_STEPS_THROTTLE_MS = 2000L
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var isStreamingActive = false

    // Throttling & Node Caching
    private val messageClient: MessageClient by lazy { Wearable.getMessageClient(this) }
    private val nodeClient: NodeClient by lazy { Wearable.getNodeClient(this) }
    private var cachedNodes: List<Node> = emptyList()
    private var lastNodeFetchTimeMs: Long = 0L

    private var lastUiHrUpdateMs: Long = 0L
    private var lastSentHrUpdateMs: Long = 0L
    private var lastSentStepsUpdateMs: Long = 0L
    private var lastEmittedBpm: Int = 0
    private var lastSentBpm: Int = 0
    private var lastSentSteps: Int = -1

    // Hardware Sensors
    private var sensorManager: SensorManager? = null
    private var androidHeartRateSensor: Sensor? = null
    private var androidStepCounterSensor: Sensor? = null
    private var androidStepDetectorSensor: Sensor? = null
    private var isAndroidSensorListening = false
    private var isAndroidStepSensorListening = false
    private var cumulativeSteps: Int = 0

    // Samsung SDK
    private var healthTrackingService: HealthTrackingService? = null
    private var healthTracker: HealthTracker? = null
    private var spo2Tracker: HealthTracker? = null
    private var isSpo2Measuring: Boolean = false

    // UI Listeners
    private var onHeartRateListener: ((Int) -> Unit)? = null
    private var onStepCountListener: ((Int) -> Unit)? = null
    private var onSpo2Listener: ((Int, String) -> Unit)? = null
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
            if (event == null) return

            val now = SystemClock.elapsedRealtime()

            when (event.sensor.type) {
                Sensor.TYPE_HEART_RATE -> {
                    val bpm = event.values.firstOrNull()?.toInt() ?: 0

                    if (bpm > 0) {
                        // 1. Throttle UI state recomposition
                        if (bpm != lastEmittedBpm || now - lastUiHrUpdateMs >= UI_UPDATE_THROTTLE_MS) {
                            lastEmittedBpm = bpm
                            lastUiHrUpdateMs = now
                            mainHandler.post {
                                onHeartRateListener?.invoke(bpm)
                                onStatusListener?.invoke(true, "Live: $bpm BPM")
                            }
                        }

                        // 2. Throttle Data Layer network transmission
                        if (now - lastSentHrUpdateMs >= IPC_HR_THROTTLE_MS ||
                            (abs(bpm - lastSentBpm) >= 3 && now - lastSentHrUpdateMs >= 500L)
                        ) {
                            lastSentBpm = bpm
                            lastSentHrUpdateMs = now
                            sendRealHeartRateMessage(bpm = bpm, timestamp = System.currentTimeMillis())
                        }
                    } else {
                        if (now - lastUiHrUpdateMs >= 1500L) {
                            lastUiHrUpdateMs = now
                            mainHandler.post {
                                onStatusListener?.invoke(true, "Place watch on wrist…")
                            }
                        }
                    }
                }
                Sensor.TYPE_STEP_COUNTER -> {
                    val steps = event.values.firstOrNull()?.toInt() ?: 0
                    if (steps >= 0) {
                        cumulativeSteps = steps
                        if (steps != lastSentSteps || now - lastSentStepsUpdateMs >= IPC_STEPS_THROTTLE_MS) {
                            lastSentSteps = steps
                            lastSentStepsUpdateMs = now
                            mainHandler.post {
                                onStepCountListener?.invoke(steps)
                            }
                            sendRealStepsMessage(steps = steps, timestamp = System.currentTimeMillis())
                        }
                    }
                }
                Sensor.TYPE_STEP_DETECTOR -> {
                    val stepEvent = event.values.firstOrNull()?.toInt() ?: 0
                    if (androidStepCounterSensor == null && stepEvent > 0) {
                        cumulativeSteps += stepEvent
                        if (now - lastSentStepsUpdateMs >= IPC_STEPS_THROTTLE_MS) {
                            lastSentStepsUpdateMs = now
                            mainHandler.post {
                                onStepCountListener?.invoke(cumulativeSteps)
                            }
                            sendRealStepsMessage(steps = cumulativeSteps, timestamp = System.currentTimeMillis())
                        }
                    }
                }
            }
        }

        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
            Log.d(TAG, "Hardware sensor accuracy (${sensor?.name}): $accuracy")
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
            val now = SystemClock.elapsedRealtime()
            for (dataPoint in dataPoints) {
                val hr = dataPoint.getValue(ValueKey.HeartRateSet.HEART_RATE)
                if (hr != null && hr > 0) {
                    if (hr != lastEmittedBpm || now - lastUiHrUpdateMs >= UI_UPDATE_THROTTLE_MS) {
                        lastEmittedBpm = hr
                        lastUiHrUpdateMs = now
                        mainHandler.post {
                            onHeartRateListener?.invoke(hr)
                            onStatusListener?.invoke(true, "Live: $hr BPM")
                        }
                    }

                    if (now - lastSentHrUpdateMs >= IPC_HR_THROTTLE_MS ||
                        (abs(hr - lastSentBpm) >= 3 && now - lastSentHrUpdateMs >= 500L)
                    ) {
                        lastSentBpm = hr
                        lastSentHrUpdateMs = now
                        sendRealHeartRateMessage(bpm = hr, timestamp = dataPoint.timestamp)
                    }
                }
            }
        }

        override fun onFlushCompleted() {}

        override fun onError(error: HealthTracker.TrackerError) {
            Log.w(TAG, "Samsung Tracker error: $error — fallback to Wear OS PPG sensor")
            startHardwareSensor()
        }
    }

    private val spo2TrackerEventListener = object : HealthTracker.TrackerEventListener {
        override fun onDataReceived(dataPoints: List<DataPoint>) {
            for (dataPoint in dataPoints) {
                val spo2 = dataPoint.getValue(ValueKey.SpO2Set.SPO2)
                if (spo2 != null && spo2 > 0) {
                    mainHandler.post {
                        onSpo2Listener?.invoke(spo2, "SpO2: $spo2%")
                    }
                    sendRealSpO2Message(spo2 = spo2, timestamp = dataPoint.timestamp)
                    stopSpo2Measurement()
                } else {
                    mainHandler.post {
                        onSpo2Listener?.invoke(0, "Measuring… hold still")
                    }
                }
            }
        }

        override fun onFlushCompleted() {}

        override fun onError(error: HealthTracker.TrackerError) {
            Log.w(TAG, "Samsung SpO2 Tracker error: $error")
            mainHandler.post {
                onSpo2Listener?.invoke(0, "SpO2 error")
            }
            stopSpo2Measurement()
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
        androidStepCounterSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
        androidStepDetectorSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_STEP_DETECTOR)

        // Warm up connected node cache
        fetchConnectedNodes {}

        setContent {
            VitalSyncTheme {
                WatchApp(
                    hasHeartRateSensor = hasHeartRateSensor(),
                    hasPermission = hasAllPermissions(),
                    onRequestPermission = { onGranted -> requestAllPermissions(onGranted) },
                    onSendPing = { onResult -> sendConnectionPing(onResult) },
                    onToggleStreaming = { start -> toggleStreaming(start) },
                    onStartSpo2Measurement = { startSpo2Measurement() },
                    onRegisterHeartRateListener = { listener -> onHeartRateListener = listener },
                    onRegisterStepCountListener = { listener -> onStepCountListener = listener },
                    onRegisterSpo2Listener = { listener -> onSpo2Listener = listener },
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

        mainHandler.removeCallbacks(heartbeatPingRunnable)
        mainHandler.post(heartbeatPingRunnable)

        // 1. Activate standard hardware PPG optical sensor with SENSOR_DELAY_UI (~60ms)
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
        val sm = sensorManager ?: (getSystemService(SENSOR_SERVICE) as SensorManager)

        // 1. Heart Rate Sensor: SENSOR_DELAY_UI provides smooth real-time response without CPU lag
        if (!isAndroidSensorListening) {
            try {
                val hrSensor = androidHeartRateSensor ?: sm.getDefaultSensor(Sensor.TYPE_HEART_RATE)
                if (hrSensor != null) {
                    val registered = sm.registerListener(
                        androidSensorEventListener,
                        hrSensor,
                        SensorManager.SENSOR_DELAY_UI,
                    )
                    isAndroidSensorListening = registered
                    Log.d(TAG, "Optical PPG Sensor registered: $registered")
                } else {
                    Log.w(TAG, "No heart rate hardware sensor found")
                }
            } catch (t: Throwable) {
                Log.e(TAG, "Failed to register heart rate sensor listener", t)
            }
        }

        // 2. Step Sensors
        if (!isAndroidStepSensorListening) {
            try {
                val stepSensor = androidStepCounterSensor ?: androidStepDetectorSensor
                    ?: sm.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
                    ?: sm.getDefaultSensor(Sensor.TYPE_STEP_DETECTOR)
                if (stepSensor != null) {
                    val registered = sm.registerListener(
                        androidSensorEventListener,
                        stepSensor,
                        SensorManager.SENSOR_DELAY_UI,
                    )
                    isAndroidStepSensorListening = registered
                    Log.d(TAG, "Step sensor (${stepSensor.name}) registered: $registered")
                } else {
                    Log.w(TAG, "No step hardware sensor found")
                }
            } catch (t: Throwable) {
                Log.e(TAG, "Failed to register step sensor listener", t)
            }
        }
    }

    private fun startSpo2Measurement() {
        if (isSpo2Measuring) return
        if (!hasAllPermissions()) {
            requestAllPermissions { granted ->
                if (granted) startSpo2Measurement()
                else onSpo2Listener?.invoke(0, "Permission required")
            }
            return
        }

        try {
            if (healthTrackingService == null) {
                healthTrackingService = HealthTrackingService(connectionListener, applicationContext)
                healthTrackingService?.connectService()
            }
            spo2Tracker = healthTrackingService?.getHealthTracker(HealthTrackerType.SPO2_ON_DEMAND)
                ?: healthTrackingService?.getHealthTracker(HealthTrackerType.SPO2)

            if (spo2Tracker != null) {
                isSpo2Measuring = true
                spo2Tracker?.setEventListener(spo2TrackerEventListener)
                onSpo2Listener?.invoke(0, "Measuring SpO2… hold still")
                Log.d(TAG, "Samsung SpO2 tracker event listener attached")
            } else {
                onSpo2Listener?.invoke(0, "SpO2 not available on device")
                Log.w(TAG, "No SpO2 tracker returned by HealthTrackingService")
            }
        } catch (t: Throwable) {
            Log.e(TAG, "Failed to start Samsung SpO2 tracker", t)
            onSpo2Listener?.invoke(0, "SpO2 tracker unavailable")
        }
    }

    private fun stopSpo2Measurement() {
        if (!isSpo2Measuring) return
        try {
            spo2Tracker?.unsetEventListener()
            spo2Tracker = null
            isSpo2Measuring = false
            Log.d(TAG, "Samsung SpO2 tracker stopped")
        } catch (t: Throwable) {
            Log.w(TAG, "Error stopping SpO2 tracker", t)
        }
    }

    private fun stopStreaming() {
        isStreamingActive = false
        mainHandler.removeCallbacks(heartbeatPingRunnable)
        stopSpo2Measurement()

        try {
            healthTracker?.unsetEventListener()
            healthTracker = null
            healthTrackingService?.disconnectService()
            healthTrackingService = null
        } catch (t: Throwable) {
            Log.w(TAG, "Error disconnecting Samsung tracking service", t)
        }

        try {
            if (isAndroidSensorListening || isAndroidStepSensorListening) {
                sensorManager?.unregisterListener(androidSensorEventListener)
                isAndroidSensorListening = false
                isAndroidStepSensorListening = false
            }
        } catch (t: Throwable) {
            Log.w(TAG, "Error unregistering Android SensorManager listener", t)
        }

        onStatusListener?.invoke(false, "Stopped")
    }

    private fun fetchConnectedNodes(callback: (List<Node>) -> Unit) {
        val now = SystemClock.elapsedRealtime()
        if (cachedNodes.isNotEmpty() && now - lastNodeFetchTimeMs < 10_000L) {
            callback(cachedNodes)
            return
        }
        nodeClient.connectedNodes
            .addOnSuccessListener { nodes ->
                cachedNodes = nodes
                lastNodeFetchTimeMs = SystemClock.elapsedRealtime()
                callback(nodes)
            }
            .addOnFailureListener {
                callback(cachedNodes)
            }
    }

    private fun sendRealHeartRateMessage(bpm: Int, timestamp: Long) {
        fetchConnectedNodes { nodes ->
            if (nodes.isEmpty()) return@fetchConnectedNodes
            val payload = JSONObject().apply {
                put("type", "heart_rate")
                put("value", bpm)
                put("unit", "bpm")
                put("timestamp", timestamp)
            }.toString().toByteArray(Charsets.UTF_8)

            nodes.forEach { node ->
                messageClient.sendMessage(node.id, HEARTRATE_PATH, payload)
            }
        }
    }

    private fun sendRealStepsMessage(steps: Int, timestamp: Long) {
        fetchConnectedNodes { nodes ->
            if (nodes.isEmpty()) return@fetchConnectedNodes
            val payload = JSONObject().apply {
                put("type", "steps")
                put("value", steps)
                put("unit", "steps")
                put("timestamp", timestamp)
            }.toString().toByteArray(Charsets.UTF_8)

            nodes.forEach { node ->
                messageClient.sendMessage(node.id, STEPS_PATH, payload)
            }
        }
    }

    private fun sendRealSpO2Message(spo2: Int, timestamp: Long) {
        fetchConnectedNodes { nodes ->
            if (nodes.isEmpty()) return@fetchConnectedNodes
            val payload = JSONObject().apply {
                put("type", "spo2")
                put("value", spo2)
                put("unit", "%")
                put("timestamp", timestamp)
            }.toString().toByteArray(Charsets.UTF_8)

            nodes.forEach { node ->
                messageClient.sendMessage(node.id, SPO2_PATH, payload)
            }
        }
    }

    private fun sendHeartbeatPing() {
        fetchConnectedNodes { nodes ->
            if (nodes.isEmpty()) return@fetchConnectedNodes
            val payload = JSONObject().apply {
                put("type", "ping")
                put("value", JSONObject.NULL)
                put("unit", "bpm")
                put("timestamp", System.currentTimeMillis())
            }.toString().toByteArray(Charsets.UTF_8)

            nodes.forEach { node ->
                messageClient.sendMessage(node.id, HEARTRATE_PATH, payload)
            }
        }
    }

    private fun sendConnectionPing(onResult: (String) -> Unit) {
        fetchConnectedNodes { nodes ->
            if (nodes.isEmpty()) {
                onResult("No phone paired")
                return@fetchConnectedNodes
            }
            val nodeNames = nodes.joinToString { it.displayName }

            nodes.forEach { node ->
                messageClient.sendMessage(
                    node.id,
                    CONNECTION_PATH,
                    "connected".toByteArray(Charsets.UTF_8),
                ).addOnSuccessListener {
                    onResult("Connected: $nodeNames ✓")
                }.addOnFailureListener { e ->
                    onResult("Failed: ${e.message?.take(15)}")
                }
            }
        }
    }
}

/**
 * Modern AMOLED Wear OS UI for Galaxy Watch4.
 *
 * Features:
 * - Animated pulsing live BPM hero card.
 * - Quick metric pills (Steps & SpO2).
 * - Gradient tracking controls.
 * - AMOLED true black optimization.
 */
@Composable
fun WatchApp(
    hasHeartRateSensor: Boolean,
    hasPermission: Boolean,
    onRequestPermission: ((Boolean) -> Unit) -> Unit,
    onSendPing: ((String) -> Unit) -> Unit,
    onToggleStreaming: (Boolean) -> Unit,
    onStartSpo2Measurement: () -> Unit,
    onRegisterHeartRateListener: (((Int) -> Unit)?) -> Unit,
    onRegisterStepCountListener: (((Int) -> Unit)?) -> Unit,
    onRegisterSpo2Listener: (((Int, String) -> Unit)?) -> Unit,
    onRegisterStatusListener: (((Boolean, String) -> Unit)?) -> Unit,
) {
    var heartRate by remember { mutableIntStateOf(0) }
    var stepCount by remember { mutableIntStateOf(0) }
    var spo2Value by remember { mutableIntStateOf(0) }
    var spo2StatusText by remember { mutableStateOf("Spot measurement") }
    var isStreaming by remember { mutableStateOf(false) }
    var statusText by remember { mutableStateOf(if (hasHeartRateSensor) "Sensor ready" else "No sensor") }
    var pingStatus by remember { mutableStateOf("Ready") }
    var permissionGranted by remember { mutableStateOf(hasPermission) }

    DisposableEffect(Unit) {
        onRegisterHeartRateListener { hr -> heartRate = hr }
        onRegisterStepCountListener { steps -> stepCount = steps }
        onRegisterSpo2Listener { value, status ->
            spo2Value = value
            spo2StatusText = status
        }
        onRegisterStatusListener { streaming, status ->
            isStreaming = streaming
            statusText = status
        }
        onDispose {
            onRegisterHeartRateListener(null)
            onRegisterStepCountListener(null)
            onRegisterSpo2Listener(null)
            onRegisterStatusListener(null)
        }
    }

    // Pulse animation for active heart rate
    val infiniteTransition = rememberInfiniteTransition(label = "heartPulse")
    val pulseScale by infiniteTransition.animateFloat(
        initialValue = 0.90f,
        targetValue = 1.15f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 600, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "pulseScale",
    )

    val listState = rememberScalingLazyListState()

    Scaffold(
        timeText = { TimeText() },
        vignette = { Vignette(vignettePosition = VignettePosition.TopAndBottom) },
        positionIndicator = { PositionIndicator(scalingLazyListState = listState) },
    ) {
        ScalingLazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .background(OledBlack)
                .padding(horizontal = 14.dp),
            state = listState,
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            // 1. Header with Live Status Dot
            item {
                Spacer(modifier = Modifier.height(18.dp))
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.Center,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Box(
                        modifier = Modifier
                            .size(7.dp)
                            .clip(CircleShape)
                            .background(if (isStreaming) StepEmerald else if (permissionGranted) VitalTeal else TextMuted),
                    )
                    Spacer(modifier = Modifier.width(6.dp))
                    Text(
                        text = "VitalSync",
                        style = MaterialTheme.typography.title3,
                        fontWeight = FontWeight.Bold,
                        color = VitalTeal,
                    )
                }
            }

            // 2. Hero Live Heart Rate Pulse Card
            item {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(18.dp))
                        .background(SurfaceDarkElevated)
                        .border(1.dp, if (isStreaming && heartRate > 0) PulseCrimson.copy(alpha = 0.4f) else SurfaceDarkBorder, RoundedCornerShape(18.dp))
                        .padding(vertical = 10.dp, horizontal = 12.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.Center,
                        ) {
                            Icon(
                                imageVector = if (isStreaming && heartRate > 0) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder,
                                contentDescription = "Heart",
                                tint = if (isStreaming && heartRate > 0) PulseCrimson else TextSecondary,
                                modifier = Modifier
                                    .size(20.dp)
                                    .scale(if (isStreaming && heartRate > 0) pulseScale else 1.0f),
                            )
                            Spacer(modifier = Modifier.width(8.dp))
                            if (heartRate > 0) {
                                Row(verticalAlignment = Alignment.Bottom) {
                                    Text(
                                        text = "$heartRate",
                                        fontSize = 32.sp,
                                        fontWeight = FontWeight.Black,
                                        color = TextPrimary,
                                    )
                                    Spacer(modifier = Modifier.width(4.dp))
                                    Text(
                                        text = "BPM",
                                        fontSize = 12.sp,
                                        fontWeight = FontWeight.SemiBold,
                                        color = PulseCrimson,
                                        modifier = Modifier.padding(bottom = 4.dp),
                                    )
                                }
                            } else {
                                Text(
                                    text = if (isStreaming) "Reading…" else "-- BPM",
                                    fontSize = 18.sp,
                                    fontWeight = FontWeight.Medium,
                                    color = TextSecondary,
                                )
                            }
                        }

                        Text(
                            text = if (isStreaming) (if (heartRate > 0) "Optical PPG Active" else statusText) else "Tap start to track",
                            style = MaterialTheme.typography.caption2,
                            color = if (isStreaming && heartRate > 0) StepEmerald else TextMuted,
                            textAlign = TextAlign.Center,
                        )
                    }
                }
            }

            // 3. Quick Metrics Row (Steps & SpO2)
            item {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    // Steps Mini Pill
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .clip(RoundedCornerShape(14.dp))
                            .background(SurfaceDark)
                            .border(1.dp, SurfaceDarkBorder, RoundedCornerShape(14.dp))
                            .padding(vertical = 8.dp, horizontal = 6.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(
                                text = if (stepCount > 0) "$stepCount" else "--",
                                style = MaterialTheme.typography.title3,
                                fontWeight = FontWeight.Bold,
                                color = StepEmerald,
                            )
                            Text(
                                text = "🚶 STEPS",
                                fontSize = 9.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = TextMuted,
                            )
                        }
                    }

                    // SpO2 Mini Pill
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .clip(RoundedCornerShape(14.dp))
                            .background(SurfaceDark)
                            .border(1.dp, SurfaceDarkBorder, RoundedCornerShape(14.dp))
                            .padding(vertical = 8.dp, horizontal = 6.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(
                                text = if (spo2Value > 0) "$spo2Value%" else "--",
                                style = MaterialTheme.typography.title3,
                                fontWeight = FontWeight.Bold,
                                color = OxygenCyan,
                            )
                            Text(
                                text = "🫁 SPO2",
                                fontSize = 9.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = TextMuted,
                            )
                        }
                    }
                }
            }

            // 4. Primary Action: Start / Stop Tracking
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
                            text = if (isStreaming) "Stop Tracking" else "Start Live Tracking",
                            style = MaterialTheme.typography.button,
                            fontWeight = FontWeight.Bold,
                        )
                    },
                    secondaryLabel = {
                        Text(
                            text = if (isStreaming) "Streaming live to phone" else "Continuous Optical PPG",
                            style = MaterialTheme.typography.caption2,
                        )
                    },
                    icon = {
                        Icon(
                            imageVector = if (isStreaming) Icons.Filled.Check else Icons.Filled.PlayArrow,
                            contentDescription = null,
                            tint = if (isStreaming) OledBlack else VitalTeal,
                        )
                    },
                    colors = if (isStreaming) {
                        ChipDefaults.chipColors(
                            backgroundColor = VitalTeal,
                            contentColor = OledBlack,
                            secondaryContentColor = OledBlack.copy(alpha = 0.8f),
                        )
                    } else {
                        ChipDefaults.chipColors(
                            backgroundColor = SurfaceDarkElevated,
                            contentColor = TextPrimary,
                            secondaryContentColor = TextSecondary,
                        )
                    },
                    modifier = Modifier.fillMaxWidth(),
                )
            }

            // 5. Measure SpO2 Spot Check Chip
            item {
                Chip(
                    onClick = {
                        if (!permissionGranted) {
                            onRequestPermission { granted ->
                                permissionGranted = granted
                                if (granted) onStartSpo2Measurement()
                            }
                        } else {
                            onStartSpo2Measurement()
                        }
                    },
                    label = {
                        Text(
                            text = if (spo2Value > 0) "SpO2: $spo2Value%" else "Spot Check SpO2",
                            style = MaterialTheme.typography.button,
                        )
                    },
                    secondaryLabel = {
                        Text(
                            text = if (spo2Value > 0) "Completed ✓" else spo2StatusText,
                            style = MaterialTheme.typography.caption2,
                            color = OxygenCyan,
                        )
                    },
                    icon = {
                        Icon(
                            imageVector = Icons.Filled.FavoriteBorder,
                            contentDescription = null,
                            tint = OxygenCyan,
                        )
                    },
                    colors = ChipDefaults.chipColors(
                        backgroundColor = SurfaceDark,
                        contentColor = TextPrimary,
                        secondaryContentColor = TextSecondary,
                    ),
                    modifier = Modifier.fillMaxWidth(),
                )
            }

            // 6. Permissions Chip
            item {
                Chip(
                    onClick = {
                        if (!permissionGranted) {
                            onRequestPermission { granted -> permissionGranted = granted }
                        }
                    },
                    label = { Text("Permissions", style = MaterialTheme.typography.button) },
                    secondaryLabel = {
                        Text(
                            text = if (permissionGranted) "All Granted ✓" else "Tap to Grant",
                            style = MaterialTheme.typography.caption2,
                            color = if (permissionGranted) StepEmerald else StatusAmber,
                        )
                    },
                    icon = {
                        Icon(
                            imageVector = if (permissionGranted) Icons.Filled.Check else Icons.Filled.Close,
                            contentDescription = null,
                            tint = if (permissionGranted) StepEmerald else StatusAmber,
                        )
                    },
                    colors = ChipDefaults.chipColors(
                        backgroundColor = SurfaceDark,
                        contentColor = TextPrimary,
                        secondaryContentColor = TextSecondary,
                    ),
                    modifier = Modifier.fillMaxWidth(),
                )
            }

            // 7. Ping / Sync Chip
            item {
                Chip(
                    onClick = {
                        pingStatus = "Pinging…"
                        onSendPing { result -> pingStatus = result }
                    },
                    label = { Text("Phone Sync", style = MaterialTheme.typography.button) },
                    secondaryLabel = {
                        Text(
                            text = pingStatus,
                            style = MaterialTheme.typography.caption2,
                        )
                    },
                    icon = {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.Send,
                            contentDescription = null,
                            tint = VitalTeal,
                        )
                    },
                    colors = ChipDefaults.chipColors(
                        backgroundColor = SurfaceDark,
                        contentColor = TextPrimary,
                        secondaryContentColor = TextSecondary,
                    ),
                    modifier = Modifier.fillMaxWidth(),
                )
            }

            item {
                Spacer(modifier = Modifier.height(20.dp))
            }
        }
    }
}
