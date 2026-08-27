/// The user's approximate physical activity context at the time a
/// measurement was taken. Populated with real detection logic in a later
/// milestone; for now it's either supplied by fake data or unknown.
enum ActivityState {
  resting,
  walking,
  running,
  unknown;

  String get label {
    switch (this) {
      case ActivityState.resting:
        return 'Resting';
      case ActivityState.walking:
        return 'Walking';
      case ActivityState.running:
        return 'Running';
      case ActivityState.unknown:
        return 'Unknown';
    }
  }
}
