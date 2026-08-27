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
 * IMPORTANT (Milestone 4 status): Samsung Health Sensor SDK integration is
 * NOT implemented here yet. Downloading the SDK requires signing in with a
 * Samsung Developer account, and without the SDK artifact its exact
 * Kotlin API surface could not be verified against live documentation -
 * guessing class/method names is explicitly disallowed by project rules.
 * See README "Galaxy Watch4 integration status" for details.
 *
 * Until that integration exists, this bridge honestly reports
 * "disconnected" and rejects connect requests with a clear error, instead
 * of fabricating a fake connection or fake heart-rate data.
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
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    // No real Watch data source is wired up yet, so the only
                    // honest state to report is "disconnected".
                    events.success("disconnected")
                }

                override fun onCancel(arguments: Any?) {
                    // Nothing to clean up: no tracker/session was started.
                }
            })
    }
}

