package com.example.vitalsync

import android.os.Handler
import android.os.Looper

/**
 * Thread-safe singleton holding the latest watch connection state and
 * heart-rate data received via [WatchListenerService].
 *
 * This is the single source of truth for watch data on the phone side.
 * [MainActivity]'s EventChannel reads from here, and the
 * [WatchListenerService] writes to it.
 *
 * STALENESS: If no message arrives within [STALENESS_TIMEOUT_MS], the
 * state auto-degrades to "disconnected" — we never silently claim to
 * be connected when we haven't heard from the watch in a while.
 */
object WatchDataHolder {

    /**
     * How long (ms) before a connection with no new messages is considered
     * stale and reverted to "disconnected". 30 seconds: the watch sends
     * pings every 10s, so missing 3 in a row means something is wrong.
     */
    private const val STALENESS_TIMEOUT_MS = 30_000L

    // --- Mutable state (all access on main thread via handler) ---

    @Volatile
    var connectionState: String = "disconnected"
        private set

    @Volatile
    var lastHeartRate: Int? = null
        private set

    @Volatile
    var lastUpdateTimestampMs: Long = 0L
        private set

    // --- Listeners ---

    private val listeners = mutableSetOf<(String) -> Unit>()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val stalenessRunnable = Runnable { degradeToDisconnected() }

    fun addListener(listener: (String) -> Unit) {
        mainHandler.post {
            listeners.add(listener)
            // Immediately emit the current state so the new subscriber is up to date.
            listener(connectionState)
        }
    }

    fun removeListener(listener: (String) -> Unit) {
        mainHandler.post { listeners.remove(listener) }
    }

    /**
     * Called by [WatchListenerService] when a message arrives from the watch.
     *
     * @param state  One of "connected", "measuring", "disconnected".
     * @param bpm    Heart rate in beats-per-minute, or null for pings.
     */
    fun updateFromMessage(state: String, bpm: Int?) {
        mainHandler.post {
            connectionState = state
            lastHeartRate = bpm
            lastUpdateTimestampMs = System.currentTimeMillis()
            notifyListeners()
            resetStalenessTimer()
        }
    }

    // --- Internal ---

    private fun notifyListeners() {
        listeners.forEach { it(connectionState) }
    }

    private fun resetStalenessTimer() {
        mainHandler.removeCallbacks(stalenessRunnable)
        mainHandler.postDelayed(stalenessRunnable, STALENESS_TIMEOUT_MS)
    }

    private fun degradeToDisconnected() {
        connectionState = "disconnected"
        lastHeartRate = null
        notifyListeners()
    }
}
