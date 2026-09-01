import '../models/activity_state.dart';
import '../models/health_measurement.dart';
import '../models/health_metric_type.dart';

/// Abstraction over any source of health measurements.
///
/// Implementations: [FakeHealthRepository] (demo data, used before hardware
/// integration) and [SamsungHealthRepository] (backed by real Galaxy Watch /
/// Samsung Health Sensor SDK + local SQLite persistence). UI & analytics code
/// depend only on this interface.
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

  /// Queries historical measurements of [type] matching time bounds and optional
  /// [activityState] or [minQualityScore], newest first.
  Future<List<HealthMeasurement>> getMeasurementsInRange(
    HealthMetricType type, {
    DateTime? startTime,
    DateTime? endTime,
    ActivityState? activityState,
    double? minQualityScore,
    int? limit,
  });

  /// Live reactive stream of the latest measurement of [type].
  Stream<HealthMeasurement?> watchLatestMeasurement(HealthMetricType type);

  /// Live reactive stream of measurement history for [type].
  Stream<List<HealthMeasurement>> watchMeasurementHistory(
    HealthMetricType type, {
    int limit = 50,
  });
}

