package com.example.vitalsync

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Flutter <-> native Android bridge entry point.
 *
 * Exposes two EventChannels and one MethodChannel used by VitalSync's
 * Galaxy Watch integration (see `lib/data/watch_bridge/watch_health_bridge.dart`):
 *
 * - [METHOD_CHANNEL] ("connect"): intended to trigger manual connection/start.
 * - [CONNECTION_EVENT_CHANNEL] (`com.vitalsync/watch_connection`):
 *   streams the current Watch connection state ("disconnected" | "connecting" | "connected" | "measuring").
 * - [DATA_EVENT_CHANNEL] (`com.vitalsync/watch_health_data`):
 *   streams standardized JSON payloads received from the watch over the Wear OS Data Layer:
 *   `{"type":"heart_rate"|"ping","value":72|null,"unit":"bpm","timestamp":<epoch_ms>}`.
 *
 * Watch data flow:
 *   Watch app -> MessageClient -> [WatchListenerService] -> [WatchDataHolder]
 *   -> EventChannels -> Flutter WatchHealthBridge -> HealthRepository -> Dashboard UI
 */
class MainActivity : FlutterActivity() {
    companion object {
        private const val METHOD_CHANNEL = "com.vitalsync/health_bridge"
        private const val CONNECTION_EVENT_CHANNEL = "com.vitalsync/watch_connection"
        private const val DATA_EVENT_CHANNEL = "com.vitalsync/watch_health_data"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "connect" -> result.error(
                        "UNAVAILABLE",
                        "Manual connect request triggered. Live data streams automatically from Galaxy Watch app.",
                        null,
                    )
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, CONNECTION_EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                private var listener: ((String) -> Unit)? = null

                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    listener = { state -> events.success(state) }
                    WatchDataHolder.addConnectionListener(listener!!)
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
