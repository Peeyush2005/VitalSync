import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/watch_connection_state.dart';
import '../../data/watch_bridge/watch_health_bridge.dart';

/// The active bridge instance used to talk to the native Android/Watch
/// integration layer.
final watchHealthBridgeProvider = Provider<WatchHealthBridge>((ref) {
  return WatchHealthBridge();
});

/// Live Galaxy Watch connection state, as reported by the native bridge.
///
/// Defaults to (and, in this milestone, always reports)
/// [WatchConnectionState.disconnected] because Samsung Health Sensor SDK
/// integration is not implemented yet - see README. The UI must treat
/// this as a normal, expected state, not an error.
final watchConnectionProvider = StreamProvider<WatchConnectionState>((ref) {
  final bridge = ref.watch(watchHealthBridgeProvider);
  return bridge.connectionState();
});
