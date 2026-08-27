/// Where a [HealthMeasurement] originated from.
enum HealthDataSource {
  galaxyWatch,
  samsungHealth,
  manualEntry,

  /// Locally generated placeholder data used before hardware integration.
  /// Must always be surfaced to the user as demo/simulated data, never as
  /// a real measurement.
  simulated;

  String get label {
    switch (this) {
      case HealthDataSource.galaxyWatch:
        return 'Galaxy Watch';
      case HealthDataSource.samsungHealth:
        return 'Samsung Health';
      case HealthDataSource.manualEntry:
        return 'Manual entry';
      case HealthDataSource.simulated:
        return 'Simulated (demo)';
    }
  }
}
