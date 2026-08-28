import '../models/health_measurement.dart';
import '../models/health_metric_type.dart';

/// Abstraction over any source of health measurements.
///
/// Implementations: [FakeHealthRepository] (demo data, used before hardware
/// integration) and [SamsungHealthRepository] (backed by real Galaxy Watch /
/// Samsung Health Sensor SDK). UI code depends only on this interface.
abstract class HealthRepository {
  /// The most recent measurement of [type] for the current user, or null
  /// if none is available yet.
  Future<HealthMeasurement?> getLatestMeasurement(HealthMetricType type);

  /// Up to [limit] most recent measurements of [type], newest first.
  /// Returns an empty list if there is no data — never fabricated values.
  Future<List<HealthMeasurement>> getMeasurementHistory(
    HealthMetricType type, {
    int limit = 50,
  });

  /// Live reactive stream of the latest measurement of [type].
  Stream<HealthMeasurement?> watchLatestMeasurement(HealthMetricType type);

  /// Live reactive stream of measurement history for [type].
  Stream<List<HealthMeasurement>> watchMeasurementHistory(
    HealthMetricType type, {
    int limit = 50,
  });
}
