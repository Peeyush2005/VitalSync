/// Connection state between VitalSync and a Galaxy Watch, as reported by
/// the native Android bridge (see `MainActivity.kt`).
///
/// This reflects the state of the Watch <-> Phone <-> Flutter pipeline as a
/// whole, not just a single measurement. The UI must handle every state
/// without crashing, especially [disconnected] (no watch paired/available)
/// which is the default/expected state on this development machine since
/// no physical Galaxy Watch4 is currently connected.
enum WatchConnectionState {
  disconnected,
  connecting,
  connected,
  measuring,
  error;

  String get label {
    switch (this) {
      case WatchConnectionState.disconnected:
        return 'Not connected';
      case WatchConnectionState.connecting:
        return 'Connecting…';
      case WatchConnectionState.connected:
        return 'Connected';
      case WatchConnectionState.measuring:
        return 'Measuring';
      case WatchConnectionState.error:
        return 'Connection error';
    }
  }

  bool get isActive =>
      this == WatchConnectionState.connected ||
      this == WatchConnectionState.measuring;
}
