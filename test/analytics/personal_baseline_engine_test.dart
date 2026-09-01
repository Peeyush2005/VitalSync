import 'package:flutter_test/flutter_test.dart';
import 'package:vitalsync/analytics/personal_baseline_engine.dart';
import 'package:vitalsync/data/models/activity_state.dart';
import 'package:vitalsync/data/models/health_data_source.dart';
import 'package:vitalsync/data/models/health_measurement.dart';
import 'package:vitalsync/data/models/health_metric_type.dart';

void main() {
  const engine = PersonalBaselineEngine();

  group('PersonalBaselineEngine - Threshold Gating', () {
    test('withholds baseline when sample count is below minimum threshold (< 5 for HR)', () {
      final now = DateTime(2026, 8, 28, 10, 0, 0);
      final insufficientSamples = [
        HealthMeasurement(
          id: 'hr_1',
          userId: 'u1',
          type: HealthMetricType.heartRate,
          value: 70.0,
          unit: 'bpm',
          timestamp: now,
          source: HealthDataSource.galaxyWatch,
          activityState: ActivityState.resting,
          qualityScore: 1.0,
        ),
        HealthMeasurement(
          id: 'hr_2',
          userId: 'u1',
          type: HealthMetricType.heartRate,
          value: 72.0,
          unit: 'bpm',
          timestamp: now.subtract(const Duration(hours: 1)),
          source: HealthDataSource.galaxyWatch,
          activityState: ActivityState.resting,
          qualityScore: 1.0,
        ),
      ];

      final baseline = engine.computeRestingHeartRateBaseline(insufficientSamples, referenceTime: now);
      expect(baseline.isEstablished, isFalse);
      expect(baseline.baselineValue, isNull);
      expect(baseline.minExpected, isNull);
      expect(baseline.maxExpected, isNull);
      expect(baseline.sampleCount, equals(2));
      expect(baseline.statusMessage, contains('Need 3 more resting readings'));
    });

    test('ignores low M8 quality (<0.60) readings during baseline calculation', () {
      final now = DateTime(2026, 8, 28, 10, 0, 0);
      final mixedQualitySamples = List.generate(
        6,
        (i) => HealthMeasurement(
          id: 'hr_$i',
          userId: 'u1',
          type: HealthMetricType.heartRate,
          value: 68.0 + i,
          unit: 'bpm',
          timestamp: now.subtract(Duration(hours: i)),
          source: HealthDataSource.galaxyWatch,
          activityState: ActivityState.resting,
          qualityScore: i < 3 ? 0.95 : 0.30, // 3 good, 3 bad
        ),
      );

      final baseline = engine.computeRestingHeartRateBaseline(mixedQualitySamples, referenceTime: now);
      expect(baseline.isEstablished, isFalse); // Only 3 valid samples >= 0.60
      expect(baseline.sampleCount, equals(3));
    });
  });

  group('PersonalBaselineEngine - Established Baselines', () {
    test('computes robust resting heart rate baseline and expected range when threshold is met', () {
      final now = DateTime(2026, 8, 28, 10, 0, 0);
      final rhrSamples = [
        68.0, 70.0, 66.0, 72.0, 69.0, 67.0, 71.0,
      ].asMap().entries.map((e) {
        return HealthMeasurement(
          id: 'hr_${e.key}',
          userId: 'u1',
          type: HealthMetricType.heartRate,
          value: e.value,
          unit: 'bpm',
          timestamp: now.subtract(Duration(hours: e.key * 2)),
          source: HealthDataSource.galaxyWatch,
          activityState: ActivityState.resting,
          qualityScore: 1.0,
          confidence: 0.95,
        );
      }).toList();

      final baseline = engine.computeRestingHeartRateBaseline(rhrSamples, referenceTime: now);

      expect(baseline.isEstablished, isTrue);
      expect(baseline.sampleCount, equals(7));
      expect(baseline.baselineValue, equals(69.0)); // Median of [66, 67, 68, 69, 70, 71, 72]
      expect(baseline.minExpected, lessThan(69.0));
      expect(baseline.maxExpected, greaterThan(69.0));
      expect(baseline.confidence, greaterThanOrEqualTo(0.75));
      expect(baseline.statusMessage, contains('Typical resting baseline: 69 bpm'));
    });

    test('computes SpO2 baseline with physiological bounds', () {
      final now = DateTime(2026, 8, 28, 10, 0, 0);
      final spo2Samples = [97.0, 98.0, 98.0, 99.0].asMap().entries.map((e) {
        return HealthMeasurement(
          id: 'spo2_${e.key}',
          userId: 'u1',
          type: HealthMetricType.spo2,
          value: e.value,
          unit: '%',
          timestamp: now.subtract(Duration(hours: e.key * 3)),
          source: HealthDataSource.galaxyWatch,
          qualityScore: 0.95,
          confidence: 0.90,
        );
      }).toList();

      final baseline = engine.computeRestingSpO2Baseline(spo2Samples, referenceTime: now);

      expect(baseline.isEstablished, isTrue);
      expect(baseline.sampleCount, equals(4));
      expect(baseline.baselineValue, equals(98.0));
      expect(baseline.minExpected, greaterThanOrEqualTo(92.0));
      expect(baseline.maxExpected, lessThanOrEqualTo(100.0));
    });
  });
}
