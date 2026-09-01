/// Physical activity context classified from multi-sensor data streams
/// (step cadence, heart rate elevation, signal quality).
///
/// Classified states:
/// - [resting]: Low motion/cadence, resting heart rate range.
/// - [walking]: Steady moderate cadence (approx. 60–120 steps/min).
/// - [active]: Elevated movement / brisk walking or general daily activity.
/// - [exercising]: High step cadence (>120 steps/min) or significantly elevated HR (>125 BPM).
/// - [sleeping]: Explicitly reserved for sustained overnight low-motion/low-HR.
///   Returns [unknown] when overnight sleep signals are insufficient.
/// - [unknown]: Insufficient sensor confidence, conflicting signals, or no data.
enum ActivityState {
  resting,
  walking,
  active,
  exercising,
  sleeping,
  unknown;

  String get label {
    switch (this) {
      case ActivityState.resting:
        return 'Resting';
      case ActivityState.walking:
        return 'Walking';
      case ActivityState.active:
        return 'Active';
      case ActivityState.exercising:
        return 'Exercising';
      case ActivityState.sleeping:
        return 'Sleeping';
      case ActivityState.unknown:
        return 'Unknown';
    }
  }
}
