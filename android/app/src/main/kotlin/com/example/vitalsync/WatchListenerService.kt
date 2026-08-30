package com.example.vitalsync

import android.util.Log
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService
import org.json.JSONObject

/**
 * Receives messages from the VitalSync watch app via the Wear OS Data Layer
 * (Google Play services, not Samsung-specific).
 *
 * This service is started automatically by the system when a message arrives
 * on any of the `/vitalsync/` paths. It runs even when [MainActivity] is
 * not in the foreground.
 *
 * Standard message protocol:
 * - Path `/vitalsync/connection`: payload = "connected" (UTF-8 text).
 * - Path `/vitalsync/heartrate`: payload = JSON:
 *   `{"type":"heart_rate"|"ping","value":72|null,"unit":"bpm","timestamp":<epoch_ms>}`.
 *
 * All received data is written to [WatchDataHolder], which in turn notifies
 * [MainActivity]'s EventChannels → Flutter WatchHealthBridge.
 */
class WatchListenerService : WearableListenerService() {

    companion object {
        private const val TAG = "WatchListenerService"
        private const val CONNECTION_PATH = "/vitalsync/connection"
        private const val HEARTRATE_PATH = "/vitalsync/heartrate"
        private const val STEPS_PATH = "/vitalsync/steps"
        private const val SPO2_PATH = "/vitalsync/spo2"
    }

    override fun onMessageReceived(messageEvent: MessageEvent) {
        super.onMessageReceived(messageEvent)

        when (messageEvent.path) {
            CONNECTION_PATH -> handleConnectionMessage(messageEvent)
            HEARTRATE_PATH -> handleHeartRateMessage(messageEvent)
            STEPS_PATH -> handleStepsMessage(messageEvent)
            SPO2_PATH -> handleSpO2Message(messageEvent)
            else -> Log.d(TAG, "Ignoring unknown path: ${messageEvent.path}")
        }
    }

    private fun handleConnectionMessage(event: MessageEvent) {
        val payload = String(event.data, Charsets.UTF_8)
        Log.d(TAG, "Connection message: $payload")
        WatchDataHolder.updateFromMessage(
            state = if (payload == "connected") "connected" else "disconnected",
            bpm = null,
            timestampMs = System.currentTimeMillis(),
            rawJson = null,
        )
    }

    private fun handleHeartRateMessage(event: MessageEvent) {
        val rawJson = String(event.data, Charsets.UTF_8)
        try {
            val json = JSONObject(rawJson)
            val type = json.optString("type", "ping")
            val value = if (!json.isNull("value")) {
                json.optInt("value")
            } else if (!json.isNull("bpm")) {
                // Backward compatibility
                json.optInt("bpm")
            } else {
                null
            }
            val timestamp = json.optLong("timestamp", System.currentTimeMillis())
            Log.d(TAG, "Heart rate message: type=$type value=$value timestamp=$timestamp")

            val state = if ((type == "heart_rate" || type == "reading") && value != null && value > 0) {
                "measuring"
            } else {
                "connected"
            }

            WatchDataHolder.updateFromMessage(
                state = state,
                bpm = value,
                timestampMs = timestamp,
                rawJson = rawJson,
            )
        } catch (e: Exception) {
            Log.w(TAG, "Failed to parse heart rate message", e)
            WatchDataHolder.updateFromMessage(
                state = "connected",
                bpm = null,
                timestampMs = System.currentTimeMillis(),
                rawJson = null,
            )
        }
    }

    private fun handleStepsMessage(event: MessageEvent) {
        val rawJson = String(event.data, Charsets.UTF_8)
        try {
            val json = JSONObject(rawJson)
            val value = if (!json.isNull("value")) json.optInt("value") else null
            val timestamp = json.optLong("timestamp", System.currentTimeMillis())
            Log.d(TAG, "Steps message: value=$value timestamp=$timestamp")

            val state = if (value != null && value >= 0) "measuring" else "connected"

            WatchDataHolder.updateFromMessage(
                state = state,
                steps = value,
                timestampMs = timestamp,
                rawJson = rawJson,
            )
        } catch (e: Exception) {
            Log.w(TAG, "Failed to parse steps message", e)
        }
    }

    private fun handleSpO2Message(event: MessageEvent) {
        val rawJson = String(event.data, Charsets.UTF_8)
        try {
            val json = JSONObject(rawJson)
            val value = if (!json.isNull("value")) json.optInt("value") else null
            val timestamp = json.optLong("timestamp", System.currentTimeMillis())
            Log.d(TAG, "SpO2 message: value=$value timestamp=$timestamp")

            val state = if (value != null && value > 0) "measuring" else "connected"

            WatchDataHolder.updateFromMessage(
                state = state,
                spo2 = value,
                timestampMs = timestamp,
                rawJson = rawJson,
            )
        } catch (e: Exception) {
            Log.w(TAG, "Failed to parse SpO2 message", e)
        }
    }
}
