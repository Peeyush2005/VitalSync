package com.example.vitalsync

import android.os.Handler
import android.os.Looper

/**
 * Thread-safe singleton holding the latest watch connection state,
 * heart-rate data, and raw JSON stream received via [WatchListenerService].
 *
 * Exposes two subscriber groups for Flutter:
 * 1. Connection state events -> `com.vitalsync/watch_connection`
 * 2. Raw health data JSON events -> `com.vitalsync/watch_health_data`
 *
 * STALENESS: If no message arrives within [STALENESS_TIMEOUT_MS] (30s),
 * the state auto-degrades to "disconnected" so the UI never silently
 * claims to be connected.
 */
object WatchDataHolder {

    private const val STALENESS_TIMEOUT_MS = 30_000L

    @Volatile
    var connectionState: String = "disconnected"
        private set

    @Volatile
    var lastHeartRate: Int? = null
        private set

    @Volatile
    var lastUpdateTimestampMs: Long = 0L
        private set

    @Volatile
    var lastDataJson: String? = null
        private set

    private val connectionListeners = mutableSetOf<(String) -> Unit>()
    private val dataListeners = mutableSetOf<(String) -> Unit>()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val stalenessRunnable = Runnable { degradeToDisconnected() }

    // --- Connection State Listeners ---

    fun addConnectionListener(listener: (String) -> Unit) {
        mainHandler.post {
            connectionListeners.add(listener)
            listener(connectionState)
        }
    }

    fun removeConnectionListener(listener: (String) -> Unit) {
        mainHandler.post { connectionListeners.remove(listener) }
    }

    // --- Data Stream Listeners ---

    fun addDataListener(listener: (String) -> Unit) {
        mainHandler.post {
            dataListeners.add(listener)
            lastDataJson?.let { listener(it) }
        }
    }

    fun removeDataListener(listener: (String) -> Unit) {
        mainHandler.post { dataListeners.remove(listener) }
    }

    /**
     * Called by [WatchListenerService] when a message arrives from the watch.
     *
     * @param state        One of "connected", "measuring", "disconnected".
     * @param bpm          Heart rate in beats-per-minute, or null for pings.
     * @param timestampMs  Timestamp of the reading in epoch milliseconds.
     * @param rawJson      The full JSON string payload to push to Flutter.
     */
    fun updateFromMessage(state: String, bpm: Int?, timestampMs: Long, rawJson: String? = null) {
        mainHandler.post {
            connectionState = state
            lastHeartRate = bpm
            lastUpdateTimestampMs = timestampMs
            if (rawJson != null) {
                lastDataJson = rawJson
                notifyDataListeners(rawJson)
            }
            notifyConnectionListeners()
            resetStalenessTimer()
        }
    }

    // --- Internal ---

    private fun notifyConnectionListeners() {
        connectionListeners.forEach { it(connectionState) }
    }

    private fun notifyDataListeners(json: String) {
        dataListeners.forEach { it(json) }
    }

    private fun resetStalenessTimer() {
        mainHandler.removeCallbacks(stalenessRunnable)
        mainHandler.postDelayed(stalenessRunnable, STALENESS_TIMEOUT_MS)
    }

    private fun degradeToDisconnected() {
        connectionState = "disconnected"
        lastHeartRate = null
        lastDataJson = null
        notifyConnectionListeners()
    }
}
