/// The kind of health measurement being recorded.
///
/// Per the project's development order, we start with heart rate and
/// activity/step data before adding other sensors.
enum HealthMetricType {
  heartRate,
  steps,
  spo2;

  /// A short, human-readable label for UI display.
  String get label {
    switch (this) {
      case HealthMetricType.heartRate:
        return 'Heart rate';
      case HealthMetricType.steps:
        return 'Steps';
      case HealthMetricType.spo2:
        return 'Blood oxygen (SpO2)';
    }
  }

  /// The standard unit measurements of this type are recorded in.
  String get defaultUnit {
    switch (this) {
      case HealthMetricType.heartRate:
        return 'bpm';
      case HealthMetricType.steps:
        return 'steps';
      case HealthMetricType.spo2:
        return '%';
    }
  }
}
