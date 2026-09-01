import 'package:flutter_test/flutter_test.dart';
import 'package:vitalsync/analytics/data_quality_engine.dart';
import 'package:vitalsync/data/models/health_data_source.dart';
import 'package:vitalsync/data/models/health_measurement.dart';
import 'package:vitalsync/data/models/health_metric_type.dart';

void main() {
  const engine = DataQualityEngine();

  group('DataQualityEngine - Heart Rate Quality & Confidence', () {
    test('rates normal resting heart rate with high quality and confidence', () {
      final now = DateTime(2026, 8, 28, 10, 0, 0);
      final m = HealthMeasurement(
        id: 'hr_1',
        userId: 'u1',
        type: HealthMetricType.heartRate,
        value: 72.0,
        unit: 'bpm',
        timestamp: now,
        source: HealthDataSource.galaxyWatch,
      );

      final assessment = engine.evaluateHeartRate(m, []);
      expect(assessment.qualityScore, equals(1.0));
      expect(assessment.confidence, equals(0.70)); // Isolated first sample
      expect(assessment.factors, contains('optimal_physiological_range'));
      expect(assessment.factors, contains('isolated_first_sample'));
    });

    test('reaches full 1.0 confidence with stable continuous 1Hz history', () {
      final now = DateTime(2026, 8, 28, 10, 0, 10);
      final history = [
        HealthMeasurement(
          id: 'hr_3',
          userId: 'u1',
          type: HealthMetricType.heartRate,
          value: 73.0,
          unit: 'bpm',
          timestamp: now.subtract(const Duration(seconds: 1)),
          source: HealthDataSource.galaxyWatch,
        ),
        HealthMeasurement(
          id: 'hr_2',
          userId: 'u1',
          type: HealthMetricType.heartRate,
          value: 72.0,
          unit: 'bpm',
          timestamp: now.subtract(const Duration(seconds: 2)),
          source: HealthDataSource.galaxyWatch,
        ),
        HealthMeasurement(
          id: 'hr_1',
          userId: 'u1',
          type: HealthMetricType.heartRate,
          value: 71.0,
          unit: 'bpm',
          timestamp: now.subtract(const Duration(seconds: 3)),
          source: HealthDataSource.galaxyWatch,
        ),
      ];

      final current = HealthMeasurement(
        id: 'hr_4',
        userId: 'u1',
        type: HealthMetricType.heartRate,
        value: 74.0,
        unit: 'bpm',
        timestamp: now,
        source: HealthDataSource.galaxyWatch,
      );

      final assessment = engine.evaluateHeartRate(current, history);
      expect(assessment.qualityScore, equals(1.0));
      expect(assessment.confidence, equals(1.0));
      expect(assessment.factors, contains('continuous_cadence'));
      expect(assessment.factors, contains('low_variance_stable_stream'));
    });

    test('penalizes quality on abrupt optical motion artifact jumps (>40 BPM)', () {
      final now = DateTime(2026, 8, 28, 10, 0, 5);
      final prev = HealthMeasurement(
        id: 'hr_prev',
        userId: 'u1',
        type: HealthMetricType.heartRate,
        value: 70.0,
        unit: 'bpm',
        timestamp: now.subtract(const Duration(seconds: 1)),
        source: HealthDataSource.galaxyWatch,
      );

      final artifact = HealthMeasurement(
        id: 'hr_jump',
        userId: 'u1',
        type: HealthMetricType.heartRate,
        value: 145.0, // +75 BPM jump in 1 second
        unit: 'bpm',
        timestamp: now,
        source: HealthDataSource.galaxyWatch,
      );

      final assessment = engine.evaluateHeartRate(artifact, [prev]);
      expect(assessment.qualityScore, lessThan(0.60));
      expect(assessment.factors, contains('abrupt_bpm_jump_artifact'));
    });

    test('degrades quality on implausible physiological values (<25 or >250)', () {
      final now = DateTime(2026, 8, 28, 10, 0, 0);
      final extreme = HealthMeasurement(
        id: 'hr_bad',
        userId: 'u1',
        type: HealthMetricType.heartRate,
        value: 12.0, // Implausible optical noise
        unit: 'bpm',
        timestamp: now,
        source: HealthDataSource.galaxyWatch,
      );

      final assessment = engine.evaluateHeartRate(extreme, []);
      expect(assessment.qualityScore, equals(0.10));
      expect(assessment.factors, contains('implausible_optical_noise'));
    });

    test('penalizes cadence for large packet gaps (>15s reconnect)', () {
      final now = DateTime(2026, 8, 28, 10, 0, 30);
      final stalePrev = HealthMeasurement(
        id: 'hr_stale',
        userId: 'u1',
        type: HealthMetricType.heartRate,
        value: 72.0,
        unit: 'bpm',
        timestamp: now.subtract(const Duration(seconds: 25)),
        source: HealthDataSource.galaxyWatch,
      );

      final current = HealthMeasurement(
        id: 'hr_new',
        userId: 'u1',
        type: HealthMetricType.heartRate,
        value: 75.0,
        unit: 'bpm',
        timestamp: now,
        source: HealthDataSource.galaxyWatch,
      );

      final assessment = engine.evaluateHeartRate(current, [stalePrev]);
      expect(assessment.qualityScore, equals(0.60));
      expect(assessment.factors, contains('stale_reconnection'));
    });
  });

  group('DataQualityEngine - Steps Quality & Confidence', () {
    test('rates normal cumulative step accumulation with high score', () {
      final now = DateTime(2026, 8, 28, 10, 0, 10);
      final prev = HealthMeasurement(
        id: 'step_prev',
        userId: 'u1',
        type: HealthMetricType.steps,
        value: 2450.0,
        unit: 'steps',
        timestamp: now.subtract(const Duration(seconds: 10)),
        source: HealthDataSource.galaxyWatch,
      );

      final current = HealthMeasurement(
        id: 'step_curr',
        userId: 'u1',
        type: HealthMetricType.steps,
        value: 2465.0, // +15 steps in 10s = 1.5 steps/sec (normal walking)
        unit: 'steps',
        timestamp: now,
        source: HealthDataSource.galaxyWatch,
      );

      final assessment = engine.evaluateSteps(current, [prev]);
      expect(assessment.qualityScore, greaterThanOrEqualTo(0.95));
      expect(assessment.confidence, greaterThanOrEqualTo(0.95));
      expect(assessment.factors, contains('normal_cadence_accumulation'));
    });

    test('flags counter reset / watch reboot when steps decrease', () {
      final now = DateTime(2026, 8, 28, 10, 0, 0);
      final prev = HealthMeasurement(
        id: 'step_before_reboot',
        userId: 'u1',
        type: HealthMetricType.steps,
        value: 5000.0,
        unit: 'steps',
        timestamp: now.subtract(const Duration(minutes: 5)),
        source: HealthDataSource.galaxyWatch,
      );

      final reset = HealthMeasurement(
        id: 'step_after_reboot',
        userId: 'u1',
        type: HealthMetricType.steps,
        value: 12.0, // Reset to 12
        unit: 'steps',
        timestamp: now,
        source: HealthDataSource.galaxyWatch,
      );

      final assessment = engine.evaluateSteps(reset, [prev]);
      expect(assessment.qualityScore, equals(0.65));
      expect(assessment.confidence, equals(0.50));
      expect(assessment.factors, contains('counter_reset_or_reboot'));
    });

    test('flags implausible vibration step rate (>6 steps/sec)', () {
      final now = DateTime(2026, 8, 28, 10, 0, 2);
      final prev = HealthMeasurement(
        id: 'step_prev',
        userId: 'u1',
        type: HealthMetricType.steps,
        value: 100.0,
        unit: 'steps',
        timestamp: now.subtract(const Duration(seconds: 2)),
        source: HealthDataSource.galaxyWatch,
      );

      final vibration = HealthMeasurement(
        id: 'step_curr',
        userId: 'u1',
        type: HealthMetricType.steps,
        value: 150.0, // 50 steps in 2 sec = 25 steps/sec
        unit: 'steps',
        timestamp: now,
        source: HealthDataSource.galaxyWatch,
      );

      final assessment = engine.evaluateSteps(vibration, [prev]);
      expect(assessment.qualityScore, equals(0.40));
      expect(assessment.confidence, equals(0.35));
      expect(assessment.factors, contains('implausible_step_cadence_vibration'));
    });
  });

  group('DataQualityEngine - SpO2 Quality & Confidence', () {
    test('rates normal healthy SpO2 (98%) with 1.0 quality', () {
      final now = DateTime(2026, 8, 28, 10, 0, 0);
      final current = HealthMeasurement(
        id: 'spo2_1',
        userId: 'u1',
        type: HealthMetricType.spo2,
        value: 98.0,
        unit: '%',
        timestamp: now,
        source: HealthDataSource.galaxyWatch,
      );

      final assessment = engine.evaluateSpO2(current, []);
      expect(assessment.qualityScore, equals(1.0));
      expect(assessment.factors, contains('normal_oxygen_saturation'));
    });

    test('boosts confidence when repeat spot-check agrees within ±2%', () {
      final now = DateTime(2026, 8, 28, 10, 5, 0);
      final prev = HealthMeasurement(
        id: 'spo2_prev',
        userId: 'u1',
        type: HealthMetricType.spo2,
        value: 97.0,
        unit: '%',
        timestamp: now.subtract(const Duration(minutes: 3)),
        source: HealthDataSource.galaxyWatch,
      );

      final current = HealthMeasurement(
        id: 'spo2_curr',
        userId: 'u1',
        type: HealthMetricType.spo2,
        value: 98.0,
        unit: '%',
        timestamp: now,
        source: HealthDataSource.galaxyWatch,
      );

      final assessment = engine.evaluateSpO2(current, [prev]);
      expect(assessment.qualityScore, equals(1.0));
      expect(assessment.confidence, equals(1.0));
      expect(assessment.factors, contains('repeat_spot_check_concordance'));
    });

    test('reduces score on severe light leak / sensor misalignment (<80%)', () {
      final now = DateTime(2026, 8, 28, 10, 0, 0);
      final low = HealthMeasurement(
        id: 'spo2_low',
        userId: 'u1',
        type: HealthMetricType.spo2,
        value: 74.0,
        unit: '%',
        timestamp: now,
        source: HealthDataSource.galaxyWatch,
      );

      final assessment = engine.evaluateSpO2(low, []);
      expect(assessment.qualityScore, equals(0.35));
      expect(assessment.factors, contains('severe_attenuation_light_leak'));
    });
  });

  group('DataQualityEngine - enrich()', () {
    test('populates qualityScore and confidence fields on HealthMeasurement', () {
      final raw = HealthMeasurement(
        id: 'hr_raw',
        userId: 'u1',
        type: HealthMetricType.heartRate,
        value: 76.0,
        unit: 'bpm',
        timestamp: DateTime(2026, 8, 28, 10, 0, 0),
        source: HealthDataSource.galaxyWatch,
      );

      final enriched = engine.enrich(raw, []);
      expect(enriched.qualityScore, isNotNull);
      expect(enriched.qualityScore, equals(1.0));
      expect(enriched.confidence, isNotNull);
      expect(enriched.confidence, equals(0.70));
    });
  });
}
