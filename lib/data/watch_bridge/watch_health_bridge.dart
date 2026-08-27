import 'package:flutter/services.dart';

import '../models/watch_connection_state.dart';

/// Thin wrapper around the Flutter <-> native Android platform channels
/// used to communicate with the Galaxy Watch bridge.
///
/// This uses only Flutter's officially supported platform channel
/// mechanism (`MethodChannel` / `EventChannel`) — see
/// https://docs.flutter.dev/platform-integration/platform-channels.
/// The native (Kotlin) side lives in `MainActivity.kt`.
///
/// IMPORTANT: As of this milestone, the native side does not yet integrate
/// the Samsung Health Sensor SDK (see README "Galaxy Watch4 integration
/// status" for why). The connection state will therefore always report
/// [WatchConnectionState.disconnected] and `requestConnect` will always
/// fail with a clear, caught error - this is expected, not a bug, and the
/// rest of the app (Dashboard, FakeHealthRepository) must keep working.
class WatchHealthBridge {
  WatchHealthBridge({
    MethodChannel? methodChannel,
    EventChannel? connectionEventChannel,
  }) : _methodChannel = methodChannel ?? const MethodChannel(_methodChannelName),
       _connectionEventChannel =
           connectionEventChannel ?? const EventChannel(_connectionChannelName);

  static const _methodChannelName = 'com.vitalsync/health_bridge';
  static const _connectionChannelName = 'com.vitalsync/watch_connection';

  final MethodChannel _methodChannel;
  final EventChannel _connectionEventChannel;

  /// A live stream of the Watch <-> Phone connection state, as reported by
  /// the native bridge. Never throws: any platform/stream error is mapped
  /// to [WatchConnectionState.error] so the UI never crashes because the
  /// watch/bridge is unavailable.
  Stream<WatchConnectionState> connectionState() {
    return _connectionEventChannel.receiveBroadcastStream().map((event) {
      switch (event) {
        case 'connecting':
          return WatchConnectionState.connecting;
        case 'connected':
          return WatchConnectionState.connected;
        case 'measuring':
          return WatchConnectionState.measuring;
        case 'disconnected':
          return WatchConnectionState.disconnected;
        default:
          return WatchConnectionState.error;
      }
    }).handleError((_) => WatchConnectionState.error);
  }

  /// Requests that the native side start tracking heart rate on a
  /// connected watch. Currently always fails with a [PlatformException]
  /// because Samsung Health Sensor SDK integration is not yet implemented
  /// (pending SDK access verification - see README).
  Future<void> requestConnect() async {
    await _methodChannel.invokeMethod<void>('connect');
  }
}
