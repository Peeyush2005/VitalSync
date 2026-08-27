import '../models/health_measurement.dart';
import '../models/health_metric_type.dart';

/// Abstraction over any source of health measurements.
///
/// Implementations: [FakeHealthRepository] (demo data, used before hardware
/// integration) and, in later milestones, a repository backed by the
/// Samsung Health SDK / Galaxy Watch bridge. UI code must depend only on
/// this interface — never on a concrete SDK.
abstract class HealthRepository {
  /// The most recent measurement of [type] for the current user, or null
  /// if none is available yet (e.g. no permissions granted, no watch
  /// connected, or no data collected).
  Future<HealthMeasurement?> getLatestMeasurement(HealthMetricType type);

  /// Up to [limit] most recent measurements of [type], newest first.
  /// Returns an empty list if there is no data — never fabricated values.
  Future<List<HealthMeasurement>> getMeasurementHistory(
    HealthMetricType type, {
    int limit = 50,
  });
}
