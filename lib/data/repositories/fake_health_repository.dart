import 'dart:math';

import '../models/activity_state.dart';
import '../models/health_data_source.dart';
import '../models/health_measurement.dart';
import '../models/health_metric_type.dart';
import 'health_repository.dart';

/// In-memory fake implementation of [HealthRepository].
///
/// Generates plausible-looking (but clearly labeled as simulated) history
/// once per instance, so repeated reads are stable within a session. This
/// exists purely to unblock UI/analytics development before real Galaxy
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
    const sampleCount = 48; // every 30 minutes over the past 24 hours
    var current = 68.0; // resting baseline bpm
    final samples = <HealthMeasurement>[];

    for (var i = 0; i < sampleCount; i++) {
      final timestamp = now.subtract(Duration(minutes: 30 * i));
      // Small random walk plus an occasional activity spike.
      final isActive = _random.nextDouble() < 0.15;
      final activityState = isActive
          ? (_random.nextBool() ? ActivityState.walking : ActivityState.running)
          : ActivityState.resting;
      final drift = (_random.nextDouble() - 0.5) * 6;
      final activityBoost = isActive ? 30 + _random.nextDouble() * 40 : 0.0;
      current = (current + drift).clamp(50, 100).toDouble();
      final value = (current + activityBoost).clamp(45, 190).toDouble();

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
          qualityScore: 0.85 + _random.nextDouble() * 0.15,
          confidence: 0.8 + _random.nextDouble() * 0.2,
        ),
      );
    }
    return samples; // already newest-first
  }

  List<HealthMeasurement> _generateStepsHistory() {
    final now = DateTime.now();
    const sampleCount = 24; // hourly buckets over the past 24 hours
    final samples = <HealthMeasurement>[];

    for (var i = 0; i < sampleCount; i++) {
      final timestamp = now.subtract(Duration(hours: i));
      final hourOfDay = timestamp.hour;
      // Roughly model daytime activity vs. nighttime rest.
      final isAwakeHour = hourOfDay >= 7 && hourOfDay <= 22;
      final baseSteps = isAwakeHour ? 200 + _random.nextInt(600) : _random.nextInt(30);

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
          qualityScore: 0.9 + _random.nextDouble() * 0.1,
          confidence: 0.85 + _random.nextDouble() * 0.15,
        ),
      );
    }
    return samples; // already newest-first
  }

  List<HealthMeasurement> _generateSpO2History() {
    final now = DateTime.now();
    const sampleCount = 8; // spot checks every few hours
    final samples = <HealthMeasurement>[];

    for (var i = 0; i < sampleCount; i++) {
      final timestamp = now.subtract(Duration(hours: 3 * i));
      // Plausible resting SpO2: 96% - 99%
      final spo2Value = 96.0 + _random.nextInt(4);

      samples.add(
        HealthMeasurement(
          id: 'spo2-$i',
          userId: _userId,
          type: HealthMetricType.spo2,
          value: spo2Value,
          unit: HealthMetricType.spo2.defaultUnit,
          timestamp: timestamp,
          source: HealthDataSource.simulated,
          qualityScore: 0.92 + _random.nextDouble() * 0.08,
          confidence: 0.9 + _random.nextDouble() * 0.1,
        ),
      );
    }
    return samples; // already newest-first
  }
}
