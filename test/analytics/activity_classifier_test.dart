import 'package:flutter_test/flutter_test.dart';
import 'package:vitalsync/analytics/activity_classifier.dart';
import 'package:vitalsync/data/models/activity_state.dart';
import 'package:vitalsync/data/models/health_data_source.dart';
import 'package:vitalsync/data/models/health_measurement.dart';
import 'package:vitalsync/data/models/health_metric_type.dart';

void main() {
  const classifier = ActivityClassifier();

  group('ActivityClassifier - Resting classification', () {
    test('classifies resting state when HR is normal and steps are zero/stationary', () {
      final now = DateTime(2026, 8, 28, 10, 0, 0);
      final hr = HealthMeasurement(
        id: 'hr_1',
        userId: 'u1',
        type: HealthMetricType.heartRate,
        value: 68.0,
        unit: 'bpm',
        timestamp: now,
        source: HealthDataSource.galaxyWatch,
        qualityScore: 1.0,
        confidence: 0.95,
      );

      final result = classifier.classify(
        latestHeartRate: hr,
        recentSteps: [],
        referenceTime: now,
      );

      expect(result.state, equals(ActivityState.resting));
      expect(result.confidence, greaterThanOrEqualTo(0.80));
      expect(result.reasons, contains('resting_heart_rate_range'));
    });
  });

  group('ActivityClassifier - Walking classification', () {
    test('classifies walking when steady cadence (60 spm) is detected', () {
      final now = DateTime(2026, 8, 28, 10, 0, 10);
      final hr = HealthMeasurement(
        id: 'hr_1',
        userId: 'u1',
        type: HealthMetricType.heartRate,
        value: 85.0,
        unit: 'bpm',
        timestamp: now,
        source: HealthDataSource.galaxyWatch,
        qualityScore: 0.95,
        confidence: 0.90,
      );

      final steps = [
        HealthMeasurement(
          id: 'step_2',
          userId: 'u1',
          type: HealthMetricType.steps,
          value: 1010.0, // +10 steps in 10s = 1.0 step/sec = 60 SPM
          unit: 'steps',
          timestamp: now,
          source: HealthDataSource.galaxyWatch,
          qualityScore: 1.0,
          confidence: 0.95,
        ),
        HealthMeasurement(
          id: 'step_1',
          userId: 'u1',
          type: HealthMetricType.steps,
          value: 1000.0,
          unit: 'steps',
          timestamp: now.subtract(const Duration(seconds: 10)),
          source: HealthDataSource.galaxyWatch,
          qualityScore: 1.0,
          confidence: 0.95,
        ),
      ];

      final result = classifier.classify(
        latestHeartRate: hr,
        recentSteps: steps,
        referenceTime: now,
      );

      expect(result.state, equals(ActivityState.walking));
      expect(result.estimatedCadenceSpm, equals(60.0));
      expect(result.confidence, greaterThanOrEqualTo(0.80));
      expect(result.reasons, contains('steady_walking_cadence'));
    });
  });

  group('ActivityClassifier - Active classification', () {
    test('classifies active state when brisk walking cadence (100 spm) is detected', () {
      final now = DateTime(2026, 8, 28, 10, 0, 6);
      final hr = HealthMeasurement(
        id: 'hr_1',
        userId: 'u1',
        type: HealthMetricType.heartRate,
        value: 105.0,
        unit: 'bpm',
        timestamp: now,
        source: HealthDataSource.galaxyWatch,
        qualityScore: 0.95,
        confidence: 0.90,
      );

      final steps = [
        HealthMeasurement(
          id: 'step_2',
          userId: 'u1',
          type: HealthMetricType.steps,
          value: 510.0, // +10 steps in 6s = 1.66 steps/sec = 100 SPM
          unit: 'steps',
          timestamp: now,
          source: HealthDataSource.galaxyWatch,
          qualityScore: 1.0,
          confidence: 0.95,
        ),
        HealthMeasurement(
          id: 'step_1',
          userId: 'u1',
          type: HealthMetricType.steps,
          value: 500.0,
          unit: 'steps',
          timestamp: now.subtract(const Duration(seconds: 6)),
          source: HealthDataSource.galaxyWatch,
          qualityScore: 1.0,
          confidence: 0.95,
        ),
      ];

      final result = classifier.classify(
        latestHeartRate: hr,
        recentSteps: steps,
        referenceTime: now,
      );

      expect(result.state, equals(ActivityState.active));
      expect(result.estimatedCadenceSpm, equals(100.0));
      expect(result.reasons, contains('brisk_walking_active_cadence'));
    });
  });

  group('ActivityClassifier - Exercising classification', () {
    test('classifies exercising on running cadence (>125 spm) with confirming elevated HR', () {
      final now = DateTime(2026, 8, 28, 10, 0, 10);
      final hr = HealthMeasurement(
        id: 'hr_1',
        userId: 'u1',
        type: HealthMetricType.heartRate,
        value: 145.0,
        unit: 'bpm',
        timestamp: now,
        source: HealthDataSource.galaxyWatch,
        qualityScore: 1.0,
        confidence: 1.0,
      );

      final steps = [
        HealthMeasurement(
          id: 'step_2',
          userId: 'u1',
          type: HealthMetricType.steps,
          value: 2025.0, // +25 steps in 10s = 2.5 steps/sec = 150 SPM
          unit: 'steps',
          timestamp: now,
          source: HealthDataSource.galaxyWatch,
          qualityScore: 1.0,
          confidence: 0.95,
        ),
        HealthMeasurement(
          id: 'step_1',
          userId: 'u1',
          type: HealthMetricType.steps,
          value: 2000.0,
          unit: 'steps',
          timestamp: now.subtract(const Duration(seconds: 10)),
          source: HealthDataSource.galaxyWatch,
          qualityScore: 1.0,
          confidence: 0.95,
        ),
      ];

      final result = classifier.classify(
        latestHeartRate: hr,
        recentSteps: steps,
        referenceTime: now,
      );

      expect(result.state, equals(ActivityState.exercising));
      expect(result.estimatedCadenceSpm, equals(150.0));
      expect(result.reasons, contains('high_cadence_exertion'));
      expect(result.reasons, contains('hr_confirms_exercise'));
    });

    test('classifies stationary high-intensity exercise when HR > 130 with high confidence and zero steps', () {
      final now = DateTime(2026, 8, 28, 10, 0, 0);
      final hr = HealthMeasurement(
        id: 'hr_1',
        userId: 'u1',
        type: HealthMetricType.heartRate,
        value: 140.0,
        unit: 'bpm',
        timestamp: now,
        source: HealthDataSource.galaxyWatch,
        qualityScore: 0.95,
        confidence: 0.90,
      );

      final result = classifier.classify(
        latestHeartRate: hr,
        recentSteps: [],
        referenceTime: now,
      );

      expect(result.state, equals(ActivityState.exercising));
      expect(result.reasons, contains('stationary_high_hr_exercise'));
    });
  });

  group('ActivityClassifier - Quality Gating & Unknown fallback', () {
    test('returns Unknown when data is stale (> 35s)', () {
      final now = DateTime(2026, 8, 28, 10, 0, 50);
      final staleHr = HealthMeasurement(
        id: 'hr_stale',
        userId: 'u1',
        type: HealthMetricType.heartRate,
        value: 70.0,
        unit: 'bpm',
        timestamp: now.subtract(const Duration(seconds: 45)),
        source: HealthDataSource.galaxyWatch,
        qualityScore: 1.0,
        confidence: 1.0,
      );

      final result = classifier.classify(
        latestHeartRate: staleHr,
        recentSteps: [],
        referenceTime: now,
      );

      expect(result.state, equals(ActivityState.unknown));
      expect(result.reasons, contains('no_fresh_sensor_data_available'));
    });

    test('does not classify exercise when elevated HR has low quality score', () {
      final now = DateTime(2026, 8, 28, 10, 0, 0);
      final noisyHr = HealthMeasurement(
        id: 'hr_noisy',
        userId: 'u1',
        type: HealthMetricType.heartRate,
        value: 140.0,
        unit: 'bpm',
        timestamp: now,
        source: HealthDataSource.galaxyWatch,
        qualityScore: 0.20, // Low quality motion artifact
        confidence: 0.30,
      );

      final result = classifier.classify(
        latestHeartRate: noisyHr,
        recentSteps: [],
        referenceTime: now,
      );

      expect(result.state, equals(ActivityState.unknown));
      expect(result.reasons, contains('low_quality_hr_degraded_weight'));
    });
  });
}
