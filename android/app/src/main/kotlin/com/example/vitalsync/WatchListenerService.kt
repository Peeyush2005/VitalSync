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
 * Message protocol (defined by the watch app):
 * - Path `/vitalsync/connection`:  payload = "connected" (UTF-8 text).
 * - Path `/vitalsync/heartrate`:   payload = JSON:
 *   `{"type":"ping"|"reading","bpm":null|<int>,"timestamp":<epoch_ms>}`.
 *
 * All received data is written to [WatchDataHolder], which in turn notifies
 * [MainActivity]'s EventChannel → Flutter WatchHealthBridge.
 */
class WatchListenerService : WearableListenerService() {

    companion object {
        private const val TAG = "WatchListenerService"
        private const val CONNECTION_PATH = "/vitalsync/connection"
        private const val HEARTRATE_PATH = "/vitalsync/heartrate"
    }

    override fun onMessageReceived(messageEvent: MessageEvent) {
        super.onMessageReceived(messageEvent)

        when (messageEvent.path) {
            CONNECTION_PATH -> handleConnectionMessage(messageEvent)
            HEARTRATE_PATH -> handleHeartRateMessage(messageEvent)
            else -> Log.d(TAG, "Ignoring unknown path: ${messageEvent.path}")
        }
    }

    private fun handleConnectionMessage(event: MessageEvent) {
        val payload = String(event.data, Charsets.UTF_8)
        Log.d(TAG, "Connection message: $payload")
        WatchDataHolder.updateFromMessage(
            state = if (payload == "connected") "connected" else "disconnected",
            bpm = null,
        )
    }

    private fun handleHeartRateMessage(event: MessageEvent) {
        try {
            val json = JSONObject(String(event.data, Charsets.UTF_8))
            val type = json.optString("type", "ping")
            val bpm = if (json.isNull("bpm")) null else json.optInt("bpm")
            Log.d(TAG, "Heart rate message: type=$type bpm=$bpm")

            WatchDataHolder.updateFromMessage(
                state = if (type == "reading" && bpm != null) "measuring" else "connected",
                bpm = bpm,
            )
        } catch (e: Exception) {
            Log.w(TAG, "Failed to parse heart rate message", e)
            // Still count as a sign of life — phone is connected.
            WatchDataHolder.updateFromMessage(state = "connected", bpm = null)
        }
    }
}
