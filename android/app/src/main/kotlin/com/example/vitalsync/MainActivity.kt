package com.example.vitalsync

import android.os.Bundle
import android.util.Log
import com.google.android.gms.wearable.MessageClient
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.Wearable
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/**
 * Flutter <-> native Android bridge entry point.
 *
 * Implements [MessageClient.OnMessageReceivedListener] to directly receive
 * messages from the Galaxy Watch via Google Play Services Wearable while
 * the app is in the foreground, complementing [WatchListenerService] which
 * handles background delivery.
 *
 * Exposes two EventChannels and one MethodChannel for Flutter:
 * - [METHOD_CHANNEL] (`com.vitalsync/health_bridge`): manual connect actions.
 * - [CONNECTION_EVENT_CHANNEL] (`com.vitalsync/watch_connection`): watch state stream.
 * - [DATA_EVENT_CHANNEL] (`com.vitalsync/watch_health_data`): live sensor JSON stream.
 */
class MainActivity : FlutterActivity(), MessageClient.OnMessageReceivedListener {

    companion object {
        private const val TAG = "MainActivityPhone"
        private const val METHOD_CHANNEL = "com.vitalsync/health_bridge"
        private const val CONNECTION_EVENT_CHANNEL = "com.vitalsync/watch_connection"
        private const val DATA_EVENT_CHANNEL = "com.vitalsync/watch_health_data"
        private const val CONNECTION_PATH = "/vitalsync/connection"
        private const val HEARTRATE_PATH = "/vitalsync/heartrate"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Wearable.getMessageClient(this).addListener(this)
        checkConnectedWatchNodes()
    }

    override fun onResume() {
        super.onResume()
        checkConnectedWatchNodes()
    }

    override fun onDestroy() {
        super.onDestroy()
        Wearable.getMessageClient(this).removeListener(this)
    }

    /**
     * Proactively checks for connected Wear OS watch nodes via Google Play Services.
     * If a paired watch node is connected, transitions state from "disconnected" to "connected".
     */
    private fun checkConnectedWatchNodes(onComplete: ((Boolean) -> Unit)? = null) {
        Wearable.getNodeClient(this).connectedNodes
            .addOnSuccessListener { nodes ->
                Log.d(TAG, "Connected wearable nodes: ${nodes.size} -> ${nodes.map { it.displayName }}")
                if (nodes.isNotEmpty()) {
                    val currentState = WatchDataHolder.connectionState
                    val newState = if (currentState == "measuring") "measuring" else "connected"
                    WatchDataHolder.updateFromMessage(
                        state = newState,
                        bpm = WatchDataHolder.lastHeartRate,
                        timestampMs = System.currentTimeMillis(),
                        rawJson = WatchDataHolder.lastDataJson,
                    )
                    onComplete?.invoke(true)
                } else {
                    onComplete?.invoke(false)
                }
            }
            .addOnFailureListener { e ->
                Log.w(TAG, "Failed to query connected wearable nodes", e)
                onComplete?.invoke(false)
            }
    }

    override fun onMessageReceived(messageEvent: MessageEvent) {
        when (messageEvent.path) {
            CONNECTION_PATH -> {
                val payload = String(messageEvent.data, Charsets.UTF_8)
                Log.d(TAG, "Foreground connection message: $payload")
                WatchDataHolder.updateFromMessage(
                    state = if (payload == "connected") "connected" else "disconnected",
                    bpm = null,
                    timestampMs = System.currentTimeMillis(),
                    rawJson = null,
                )
            }
            HEARTRATE_PATH -> {
                val rawJson = String(messageEvent.data, Charsets.UTF_8)
                try {
                    val json = JSONObject(rawJson)
                    val type = json.optString("type", "ping")
                    val value = if (!json.isNull("value")) {
                        json.optInt("value")
                    } else if (!json.isNull("bpm")) {
                        json.optInt("bpm")
                    } else {
                        null
                    }
                    val timestamp = json.optLong("timestamp", System.currentTimeMillis())
                    val state = if ((type == "heart_rate" || type == "reading") && value != null && value > 0) {
                        "measuring"
                    } else {
                        "connected"
                    }
                    Log.d(TAG, "Foreground HR message: state=$state value=$value timestamp=$timestamp")
                    WatchDataHolder.updateFromMessage(
                        state = state,
                        bpm = value,
                        timestampMs = timestamp,
                        rawJson = rawJson,
                    )
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to parse foreground message", e)
                    WatchDataHolder.updateFromMessage(
                        state = "connected",
                        bpm = null,
                        timestampMs = System.currentTimeMillis(),
                        rawJson = null,
                    )
                }
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "connect" -> {
                        checkConnectedWatchNodes { isConnected ->
                            result.success(isConnected)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, CONNECTION_EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                private var listener: ((String) -> Unit)? = null

                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    listener = { state -> events.success(state) }
                    WatchDataHolder.addConnectionListener(listener!!)
                    checkConnectedWatchNodes()
                }

                override fun onCancel(arguments: Any?) {
                    listener?.let { WatchDataHolder.removeConnectionListener(it) }
                    listener = null
                }
            })

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, DATA_EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                private var listener: ((String) -> Unit)? = null

                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    listener = { json -> events.success(json) }
                    WatchDataHolder.addDataListener(listener!!)
                }

                override fun onCancel(arguments: Any?) {
                    listener?.let { WatchDataHolder.removeDataListener(it) }
                    listener = null
                }
            })
    }
}
