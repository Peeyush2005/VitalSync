import 'dart:math';

import '../models/activity_state.dart';
import '../models/health_data_source.dart';
import '../models/health_measurement.dart';
import '../models/health_metric_type.dart';
import 'health_repository.dart';

/// In-memory fake implementation of [HealthRepository].
///
/// Generates plausible-looking (but clearly labeled as simulated) multi-day
/// history once per instance, so repeated reads are stable within a session:
/// - Heart Rate: ~7 days of periodic resting & active readings (every ~30-60 min).
/// - Steps: ~7 days of hourly buckets modeling daily activity cycles.
/// - SpO2: ~14 days of sparse spot checks (1-3 per day).
///
/// This exists purely to unblock UI/analytics development before real Galaxy
/// Watch / Samsung Health integration lands (Milestones 4-6).
class FakeHealthRepository implements HealthRepository {
  FakeHealthRepository({this._userId = 'demo-user', Random? random})
    : _random = random ?? Random(42) {
    _history = {
      HealthMetricType.heartRate: _generateHeartRateHistory(),
      HealthMetricType.steps: _generateStepsHistory(),
      HealthMetricType.spo2: _generateSpO2History(),
    };
  }

  final String _userId;
  final Random _random;
  late final Map<HealthMetricType, List<HealthMeasurement>> _history;

  @override
  Future<HealthMeasurement?> getLatestMeasurement(
    HealthMetricType type,
  ) async {
    final history = _history[type] ?? const [];
    return history.isEmpty ? null : history.first;
  }

  @override
  Future<List<HealthMeasurement>> getMeasurementHistory(
    HealthMetricType type, {
    int limit = 50,
  }) async {
    final history = _history[type] ?? const [];
    return history.take(limit).toList(growable: false);
  }

  @override
  Future<List<HealthMeasurement>> getMeasurementsInRange(
    HealthMetricType type, {
    DateTime? startTime,
    DateTime? endTime,
    ActivityState? activityState,
    double? minQualityScore,
    int? limit,
  }) async {
    final history = _history[type] ?? const [];
    var filtered = history.where((m) {
      if (startTime != null && m.timestamp.isBefore(startTime)) return false;
      if (endTime != null && m.timestamp.isAfter(endTime)) return false;
      if (activityState != null && m.activityState != activityState) return false;
      if (minQualityScore != null && (m.qualityScore ?? 1.0) < minQualityScore) return false;
      return true;
    });

    if (limit != null) {
      filtered = filtered.take(limit);
    }
    return filtered.toList(growable: false);
  }

  @override
  Stream<HealthMeasurement?> watchLatestMeasurement(HealthMetricType type) {
    return Stream.fromFuture(getLatestMeasurement(type));
  }

  @override
  Stream<List<HealthMeasurement>> watchMeasurementHistory(
    HealthMetricType type, {
    int limit = 50,
  }) {
    return Stream.fromFuture(getMeasurementHistory(type, limit: limit));
  }

  List<HealthMeasurement> _generateHeartRateHistory() {
    final now = DateTime.now();
    // 7 days of data at ~1-2 readings per hour = ~200 samples
    const sampleCount = 168; // 7 days * 24 hours
    var restingBase = 68.0;
    final samples = <HealthMeasurement>[];

    for (var i = 0; i < sampleCount; i++) {
      final timestamp = now.subtract(Duration(hours: i));
      final hourOfDay = timestamp.hour;

      // Realistic circadian drift + day-to-day mild fluctuation
      final isNight = hourOfDay < 6 || hourOfDay > 23;
      final isActive = !isNight && _random.nextDouble() < 0.20;
      final activityState = isActive
          ? (_random.nextBool() ? ActivityState.walking : ActivityState.exercising)
          : ActivityState.resting;

      final drift = (_random.nextDouble() - 0.5) * 3;
      restingBase = (restingBase + drift).clamp(62.0, 74.0).toDouble();

      final activeBoost = isActive ? 25.0 + _random.nextDouble() * 35 : 0.0;
      final nightDip = isNight ? -4.0 - _random.nextDouble() * 4.0 : 0.0;
      final value = (restingBase + activeBoost + nightDip).clamp(48.0, 180.0);

      samples.add(
        HealthMeasurement(
          id: 'hr-$i',
          userId: _userId,
          type: HealthMetricType.heartRate,
          value: double.parse(value.toStringAsFixed(1)),
          unit: HealthMetricType.heartRate.defaultUnit,
          timestamp: timestamp,
          source: HealthDataSource.simulated,
          activityState: activityState,
          qualityScore: 0.88 + _random.nextDouble() * 0.12,
          confidence: 0.85 + _random.nextDouble() * 0.15,
        ),
      );
    }
    return samples; // newest-first
  }

  List<HealthMeasurement> _generateStepsHistory() {
    final now = DateTime.now();
    // 7 days of hourly buckets = 168 samples
    const sampleCount = 168;
    final samples = <HealthMeasurement>[];

    for (var i = 0; i < sampleCount; i++) {
      final timestamp = now.subtract(Duration(hours: i));
      final hourOfDay = timestamp.hour;
      final isAwakeHour = hourOfDay >= 7 && hourOfDay <= 22;

      final baseSteps = isAwakeHour
          ? 250 + _random.nextInt(650)
          : _random.nextInt(25);

      samples.add(
        HealthMeasurement(
          id: 'steps-$i',
          userId: _userId,
          type: HealthMetricType.steps,
          value: baseSteps.toDouble(),
          unit: HealthMetricType.steps.defaultUnit,
          timestamp: timestamp,
          source: HealthDataSource.simulated,
          activityState: baseSteps > 400
              ? ActivityState.walking
              : ActivityState.resting,
          qualityScore: 0.92 + _random.nextDouble() * 0.08,
          confidence: 0.90 + _random.nextDouble() * 0.10,
        ),
      );
    }
    return samples; // newest-first
  }

  List<HealthMeasurement> _generateSpO2History() {
    final now = DateTime.now();
    // 14 days of spot checks (~2-3 checks per day = ~35 samples)
    const sampleCount = 35;
    final samples = <HealthMeasurement>[];

    for (var i = 0; i < sampleCount; i++) {
      // Space them out over 14 days (~9.6 hours apart)
      final timestamp = now.subtract(Duration(minutes: (i * 580) + _random.nextInt(60)));
      final spo2Value = 96.0 + _random.nextInt(4); // 96 to 99%

      samples.add(
        HealthMeasurement(
          id: 'spo2-$i',
          userId: _userId,
          type: HealthMetricType.spo2,
          value: spo2Value,
          unit: HealthMetricType.spo2.defaultUnit,
          timestamp: timestamp,
          source: HealthDataSource.simulated,
          qualityScore: 0.94 + _random.nextDouble() * 0.06,
          confidence: 0.92 + _random.nextDouble() * 0.08,
        ),
      );
    }
    return samples; // newest-first
  }
}
