package com.example.vitalsync

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Flutter <-> native Android bridge entry point.
 *
 * This currently exposes two channels used by VitalSync's Galaxy Watch
 * integration (see lib/data/watch_bridge/watch_health_bridge.dart):
 *
 * - [METHOD_CHANNEL] ("connect"): intended to start heart-rate tracking on
 *   a paired Galaxy Watch via the Samsung Health Sensor SDK.
 * - [CONNECTION_EVENT_CHANNEL]: streams the current Watch connection
 *   state ("disconnected" | "connecting" | "connected" | "measuring").
 *
 * Watch data flow:
 *   Watch app -> MessageClient -> [WatchListenerService] -> [WatchDataHolder]
 *   -> this EventChannel -> Flutter WatchHealthBridge -> Dashboard UI
 *
 * IMPORTANT (Milestone 4 status): Samsung Health Sensor SDK integration is
 * NOT implemented here yet. The "connect" MethodChannel still returns an
 * error. However, the EventChannel now reads **real** connection state from
 * [WatchDataHolder], which is updated by [WatchListenerService] whenever
 * a message arrives from the watch via Wear OS Data Layer.
 *
 * Without a second Android phone paired to the watch, end-to-end message
 * delivery cannot be verified — but the plumbing is complete and honest.
 */
class MainActivity : FlutterActivity() {
    companion object {
        private const val METHOD_CHANNEL = "com.vitalsync/health_bridge"
        private const val CONNECTION_EVENT_CHANNEL = "com.vitalsync/watch_connection"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "connect" -> result.error(
                        "UNAVAILABLE",
                        "Samsung Health Sensor SDK integration is not implemented yet. " +
                            "See README for details.",
                        null,
                    )
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, CONNECTION_EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                private var listener: ((String) -> Unit)? = null

                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    // Register with WatchDataHolder — it will immediately emit the
                    // current state and then push updates as they arrive from the
                    // WatchListenerService.
                    listener = { state -> events.success(state) }
                    WatchDataHolder.addListener(listener!!)
                }

                override fun onCancel(arguments: Any?) {
                    listener?.let { WatchDataHolder.removeListener(it) }
                    listener = null
                }
            })
    }
}
