import 'package:flutter_test/flutter_test.dart';
import 'package:vitalsync/analytics/activity_classifier.dart';
import 'package:vitalsync/analytics/anomaly_engine.dart';
import 'package:vitalsync/analytics/personal_baseline_engine.dart';
import 'package:vitalsync/analytics/trend_engine.dart';
import 'package:vitalsync/data/models/activity_state.dart';
import 'package:vitalsync/data/models/health_data_source.dart';
import 'package:vitalsync/data/models/health_measurement.dart';
import 'package:vitalsync/data/models/health_metric_type.dart';

void main() {
  const engine = AnomalyEngine();
  final now = DateTime(2026, 9, 2, 12, 0, 0);

  // Established HR baseline: 68 bpm, expected range 60–76 (half-width 8).
  final hrBaseline = PersonalBaseline(
    type: HealthMetricType.heartRate,
    isEstablished: true,
    baselineValue: 68.0,
    minExpected: 60.0,
    maxExpected: 76.0,
    standardDeviation: 4.0,
    sampleCount: 20,
    confidence: 0.95,
    statusMessage: 'Typical resting baseline: 68 bpm',
    calculatedAt: now,
  );

  final unestablishedBaseline = PersonalBaseline(
    type: HealthMetricType.heartRate,
    isEstablished: false,
    sampleCount: 2,
    confidence: 0.2,
    statusMessage: 'Need more data',
    calculatedAt: now,
  );

  final spo2Baseline = PersonalBaseline(
    type: HealthMetricType.spo2,
    isEstablished: true,
    baselineValue: 98.0,
    minExpected: 95.0,
    maxExpected: 100.0,
    standardDeviation: 1.0,
    sampleCount: 10,
    confidence: 0.90,
    statusMessage: 'Resting SpO2 baseline: 98%',
    calculatedAt: now,
  );

  final stepsBaseline = PersonalBaseline(
    type: HealthMetricType.steps,
    isEstablished: true,
    baselineValue: 7000.0,
    minExpected: 4500.0,
    maxExpected: 10500.0,
    standardDeviation: 1500.0,
    sampleCount: 14,
    confidence: 0.92,
    statusMessage: 'Daily activity baseline: 7000 steps',
    calculatedAt: now,
  );

  const restingActivity = ActivityClassificationResult(
    state: ActivityState.resting,
    confidence: 0.9,
    reasons: ['resting'],
  );

  const exercisingActivity = ActivityClassificationResult(
    state: ActivityState.exercising,
    confidence: 0.9,
    reasons: ['high_cadence_exertion'],
  );

  HealthMeasurement hrMeasurement(
    double value, {
    double quality = 0.95,
    Duration age = const Duration(minutes: 1),
  }) {
    return HealthMeasurement(
      id: 'hr_test',
      userId: 'u1',
      type: HealthMetricType.heartRate,
      value: value,
      unit: 'bpm',
      timestamp: now.subtract(age),
      source: HealthDataSource.galaxyWatch,
      activityState: ActivityState.resting,
      qualityScore: quality,
      confidence: quality,
    );
  }

  group('AnomalyEngine - Quality Gate (structural, first, always)', () {
    test('never flags an extreme value when M8 quality is below 0.60 — '
        'no code path can bypass the gate', () {
      // 230 bpm with terrible quality (e.g. off-body / loosened watch).
      final result = engine.evaluate(
        measurement: hrMeasurement(230.0, quality: 0.30),
        baseline: hrBaseline,
        activity: restingActivity,
        referenceTime: now,
      );

      expect(result.isAnomaly, isFalse);
      expect(result.severity, equals(AnomalySeverity.none));
      expect(result.confidence, equals(0.0));
      expect(result.reasons, contains('quality_gate_blocked'));
      expect(result.reasons, contains('low_quality_reading_not_anomaly'));
    });

    test('gates at exactly the 0.60 threshold boundary (0.59 blocked)', () {
      final result = engine.evaluate(
        measurement: hrMeasurement(120.0, quality: 0.59),
        baseline: hrBaseline,
        activity: restingActivity,
        referenceTime: now,
      );
      expect(result.isAnomaly, isFalse);
      expect(result.reasons, contains('quality_gate_blocked'));
    });

    test('a confirmed suddenShift trend cannot force a low-quality '
        'reading into an anomaly', () {
      final trend = MetricTrend(
        type: HealthMetricType.heartRate,
        direction: TrendDirection.suddenShift,
        confidence: 0.9,
        headline: 'Acute elevation detected',
        message: 'Worth monitoring if sustained.',
        factors: [],
        zScore: 3.5,
        calculatedAt: now,
      );

      final result = engine.evaluate(
        measurement: hrMeasurement(130.0, quality: 0.45),
        baseline: hrBaseline,
        trend: trend,
        activity: restingActivity,
        referenceTime: now,
      );

      expect(result.isAnomaly, isFalse);
      expect(result.reasons, contains('quality_gate_blocked'));
    });

    test('null measurement (no data) is a gated not-anomaly, never fabricated',
        () {
      final result = engine.evaluate(
        measurement: null,
        baseline: hrBaseline,
        activity: restingActivity,
        referenceTime: now,
      );

      expect(result.isAnomaly, isFalse);
      expect(result.reasons, contains('no_measurement_available'));
    });
  });

  group('AnomalyEngine - Baseline & Recency Gating', () {
    test('unestablished baseline never produces an anomaly', () {
      final result = engine.evaluate(
        measurement: hrMeasurement(130.0),
        baseline: unestablishedBaseline,
        activity: restingActivity,
        referenceTime: now,
      );

      expect(result.isAnomaly, isFalse);
      expect(result.reasons, contains('baseline_not_established'));
    });

    test('stale measurement (> 10 minutes old) is not evaluated as current',
        () {
      final result = engine.evaluate(
        measurement: hrMeasurement(130.0, age: const Duration(minutes: 30)),
        baseline: hrBaseline,
        activity: restingActivity,
        referenceTime: now,
      );

      expect(result.isAnomaly, isFalse);
      expect(result.reasons, contains('measurement_stale'));
    });
  });

  group('AnomalyEngine - Activity Context Suppression (M9)', () {
    test('elevated HR during Exercising is NOT flagged as anomalous', () {
      // 160 bpm at rest would be severe; while exercising it's expected.
      final result = engine.evaluate(
        measurement: hrMeasurement(160.0),
        baseline: hrBaseline,
        activity: exercisingActivity,
        referenceTime: now,
      );

      expect(result.isAnomaly, isFalse);
      expect(
        result.reasons.any((r) => r.startsWith('elevation_explained_by_activity')),
        isTrue,
      );
    });

    test('elevated HR during Walking is NOT flagged as anomalous', () {
      const walkingActivity = ActivityClassificationResult(
        state: ActivityState.walking,
        confidence: 0.9,
        reasons: ['steady_walking_cadence'],
      );

      final result = engine.evaluate(
        measurement: hrMeasurement(110.0),
        baseline: hrBaseline,
        activity: walkingActivity,
        referenceTime: now,
      );

      expect(result.isAnomaly, isFalse);
    });

    test('LOW-side HR deviation is never explained away by activity '
        '(activity only explains elevation)', () {
      // A resting-HR crash to 40 bpm is unusual even while exercising.
      final result = engine.evaluate(
        measurement: hrMeasurement(40.0),
        baseline: hrBaseline,
        activity: exercisingActivity,
        referenceTime: now,
      );

      expect(result.isAnomaly, isTrue);
      expect(result.severity, equals(AnomalySeverity.severe));
    });

    test('elevated HR while Resting IS flagged (no activity excuse)', () {
      final result = engine.evaluate(
        measurement: hrMeasurement(110.0),
        baseline: hrBaseline,
        activity: restingActivity,
        referenceTime: now,
      );

      expect(result.isAnomaly, isTrue);
      expect(result.severity, equals(AnomalySeverity.severe));
    });
  });

  group('AnomalyEngine - Severity Scale (documented thresholds)', () {
    // HR baseline range 60–76 => half-width 8.
    // mild: beyond bound by (0, 2] ; moderate: (2, 6]; severe: > 6.
    test('mild: 78 bpm — 2 bpm beyond the upper bound (ratio 0.25 boundary)', () {
      final result = engine.evaluate(
        measurement: hrMeasurement(78.0),
        baseline: hrBaseline,
        activity: restingActivity,
        referenceTime: now,
      );

      expect(result.isAnomaly, isTrue);
      expect(result.severity, equals(AnomalySeverity.mild));
      expect(result.deviation, equals(2.0));
      expect(result.anomalyKey, equals('heartRate:high'));
    });

    test('moderate: 82 bpm — 6 bpm beyond the upper bound (ratio 0.75 boundary)',
        () {
      final result = engine.evaluate(
        measurement: hrMeasurement(82.0),
        baseline: hrBaseline,
        activity: restingActivity,
        referenceTime: now,
      );

      expect(result.isAnomaly, isTrue);
      expect(result.severity, equals(AnomalySeverity.moderate));
      expect(result.deviation, equals(6.0));
    });

    test('severe: 85 bpm — more than 75% of the half-width beyond the bound',
        () {
      final result = engine.evaluate(
        measurement: hrMeasurement(85.0),
        baseline: hrBaseline,
        activity: restingActivity,
        referenceTime: now,
      );

      expect(result.isAnomaly, isTrue);
      expect(result.severity, equals(AnomalySeverity.severe));
    });

    test('within-range readings are not anomalies (59–76 is normal)', () {
      for (final value in [62.0, 68.0, 74.0, 76.0]) {
        final result = engine.evaluate(
          measurement: hrMeasurement(value),
          baseline: hrBaseline,
          activity: restingActivity,
          referenceTime: now,
        );
        expect(result.isAnomaly, isFalse, reason: '$value bpm should be normal');
        expect(result.reasons, contains('within_expected_range'));
      }
    });

    test('low-side SpO2 deviation maps to the same ratio scale', () {
      // SpO2 range 95–100 => half-width 2.5. 92% is 3 beyond => ratio 1.2 => severe.
      final spo2Measurement = HealthMeasurement(
        id: 'spo2_test',
        userId: 'u1',
        type: HealthMetricType.spo2,
        value: 92.0,
        unit: '%',
        timestamp: now.subtract(const Duration(minutes: 1)),
        source: HealthDataSource.galaxyWatch,
        qualityScore: 0.95,
        confidence: 0.95,
      );

      final result = engine.evaluate(
        measurement: spo2Measurement,
        baseline: spo2Baseline,
        activity: restingActivity,
        referenceTime: now,
      );

      expect(result.isAnomaly, isTrue);
      expect(result.severity, equals(AnomalySeverity.severe));
      expect(result.anomalyKey, equals('spo2:low'));
      expect(result.deviation, equals(-3.0));
    });
  });

  group('AnomalyEngine - M11 Trend Corroboration & Escalation', () {
    test('a confirmed suddenShift trend escalates an isolated deviation '
        'one severity level (sustained pattern, not a one-off blip)', () {
      // 78 bpm alone is mild; as part of a confirmed acute pattern it's moderate.
      final trend = MetricTrend(
        type: HealthMetricType.heartRate,
        direction: TrendDirection.suddenShift,
        confidence: 0.85,
        headline: 'Acute elevation detected',
        message: 'Worth monitoring if sustained.',
        factors: [],
        zScore: 2.5,
        calculatedAt: now,
      );

      final result = engine.evaluate(
        measurement: hrMeasurement(78.0),
        baseline: hrBaseline,
        trend: trend,
        activity: restingActivity,
        referenceTime: now,
      );

      expect(result.isAnomaly, isTrue);
      expect(result.severity, equals(AnomalySeverity.moderate));
      expect(result.anomalyKey, equals('heartRate:high:pattern'));
      expect(result.reasons, contains('part_of_confirmed_suddenShift_pattern'));
    });

    test('a low-confidence trend does not escalate or create anomalies', () {
      final weakTrend = MetricTrend(
        type: HealthMetricType.heartRate,
        direction: TrendDirection.suddenShift,
        confidence: 0.30, // below minTrendConfidence
        headline: 'Acute elevation detected',
        message: 'Worth monitoring if sustained.',
        factors: [],
        zScore: 2.5,
        calculatedAt: now,
      );

      // 68 bpm is within range: weak trend alone must not fabricate an anomaly.
      final result = engine.evaluate(
        measurement: hrMeasurement(68.0),
        baseline: hrBaseline,
        trend: weakTrend,
        activity: restingActivity,
        referenceTime: now,
      );

      expect(result.isAnomaly, isFalse);
      expect(result.reasons, contains('within_expected_range'));
    });

    test('a confident suddenShift trend alone surfaces a pattern anomaly '
        'even when the single reading is within range', () {
      final trend = MetricTrend(
        type: HealthMetricType.heartRate,
        direction: TrendDirection.suddenShift,
        confidence: 0.90,
        headline: 'Acute elevation detected',
        message: 'Worth monitoring if sustained.',
        factors: [],
        zScore: 3.0,
        calculatedAt: now,
      );

      final result = engine.evaluate(
        measurement: hrMeasurement(75.0), // within 60–76 range
        baseline: hrBaseline,
        trend: trend,
        activity: restingActivity,
        referenceTime: now,
      );

      expect(result.isAnomaly, isTrue);
      expect(result.reasons, contains('trend_confirmed_suddenShift_pattern'));
      expect(result.anomalyKey, equals('heartRate:high:pattern'));
    });

    test('null trend (analysis unavailable) degrades gracefully to '
        'baseline-only evaluation', () {
      final result = engine.evaluate(
        measurement: hrMeasurement(82.0),
        baseline: hrBaseline,
        trend: null,
        activity: restingActivity,
        referenceTime: now,
      );

      expect(result.isAnomaly, isTrue);
      expect(result.severity, equals(AnomalySeverity.moderate));
    });

    test('steps: cumulative counter readings skip point-deviation checks; '
        'only a confirmed trend pattern can flag steps', () {
      // A mid-day cumulative count of 12000 is meaningless vs a 10500 daily
      // total baseline — must NOT be flagged by point comparison.
      final stepsMeasurement = HealthMeasurement(
        id: 'steps_test',
        userId: 'u1',
        type: HealthMetricType.steps,
        value: 12000.0,
        unit: 'steps',
        timestamp: now.subtract(const Duration(minutes: 1)),
        source: HealthDataSource.galaxyWatch,
        qualityScore: 0.95,
        confidence: 0.95,
      );

      final result = engine.evaluate(
        measurement: stepsMeasurement,
        baseline: stepsBaseline,
        activity: restingActivity,
        referenceTime: now,
      );

      expect(result.isAnomaly, isFalse);
      expect(result.reasons, contains('within_expected_range'));

      // But a confirmed steps trend pattern does surface.
      final trend = MetricTrend(
        type: HealthMetricType.steps,
        direction: TrendDirection.suddenShift,
        confidence: 0.85,
        headline: 'Acute elevation detected',
        message: 'Worth monitoring if sustained.',
        factors: [],
        zScore: 2.6,
        calculatedAt: now,
      );

      final patternResult = engine.evaluate(
        measurement: stepsMeasurement,
        baseline: stepsBaseline,
        trend: trend,
        activity: restingActivity,
        referenceTime: now,
      );

      expect(patternResult.isAnomaly, isTrue);
      expect(patternResult.anomalyKey, equals('steps:high:pattern'));
    });
  });

  group('AnomalyEngine - Ongoing vs. New Anomaly Identity', () {
    test('the same sustained deviation is identified as ONE ongoing anomaly, '
        'not re-flagged as fresh on every new sample', () {
      final first = engine.evaluate(
        measurement: hrMeasurement(85.0, age: const Duration(minutes: 5)),
        baseline: hrBaseline,
        activity: restingActivity,
        referenceTime: now,
      );
      expect(first.isAnomaly, isTrue);
      expect(first.isOngoing, isFalse);

      // Sustained condition 2 minutes later: same key within the window.
      final second = engine.evaluate(
        measurement: hrMeasurement(86.0, age: const Duration(minutes: 3)),
        baseline: hrBaseline,
        activity: restingActivity,
        previous: first,
        referenceTime: now,
      );

      expect(second.isAnomaly, isTrue);
      expect(second.isOngoing, isTrue);
      expect(second.anomalyKey, equals(first.anomalyKey));
      expect(second.firstDetectedAt, equals(first.firstDetectedAt));
      expect(second.reasons, contains('ongoing_anomaly_continuation'));
    });

    test('an anomaly after the continuity window expires is a NEW anomaly',
        () {
      final earlier = now.subtract(const Duration(hours: 7));
      final firstMeasurement = HealthMeasurement(
        id: 'hr_test_1',
        userId: 'u1',
        type: HealthMetricType.heartRate,
        value: 85.0,
        unit: 'bpm',
        timestamp: earlier,
        source: HealthDataSource.galaxyWatch,
        activityState: ActivityState.resting,
        qualityScore: 0.95,
        confidence: 0.95,
      );

      final first = engine.evaluate(
        measurement: firstMeasurement,
        baseline: hrBaseline,
        activity: restingActivity,
        referenceTime: earlier,
      );
      expect(first.isAnomaly, isTrue);

      final later = engine.evaluate(
        measurement: hrMeasurement(85.0, age: const Duration(minutes: 1)),
        baseline: hrBaseline,
        activity: restingActivity,
        previous: first,
        referenceTime: now,
      );

      expect(later.isAnomaly, isTrue);
      expect(later.isOngoing, isFalse);
      expect(later.firstDetectedAt, isNot(equals(first.firstDetectedAt)));
    });

    test('opposite-polarity deviations are distinct anomalies (different key)',
        () {
      final high = engine.evaluate(
        measurement: hrMeasurement(85.0, age: const Duration(minutes: 4)),
        baseline: hrBaseline,
        activity: restingActivity,
        referenceTime: now,
      );

      final low = engine.evaluate(
        measurement: hrMeasurement(52.0, age: const Duration(minutes: 2)),
        baseline: hrBaseline,
        activity: restingActivity,
        previous: high,
        referenceTime: now,
      );

      expect(high.anomalyKey, equals('heartRate:high'));
      expect(low.anomalyKey, equals('heartRate:low'));
      expect(low.isOngoing, isFalse);
    });
  });

  group('AnomalyEngine - Confidence Combination', () {
    test('anomaly confidence reflects combined input confidences '
        '(quality × baseline × trend contribution)', () {
      final strongTrend = MetricTrend(
        type: HealthMetricType.heartRate,
        direction: TrendDirection.suddenShift,
        confidence: 0.9,
        headline: '',
        message: '',
        factors: [],
        zScore: 2.5,
        calculatedAt: now,
      );
      final strong = engine.evaluate(
        measurement: hrMeasurement(85.0, quality: 0.95),
        baseline: hrBaseline,
        trend: strongTrend,
        activity: restingActivity,
        referenceTime: now,
      );

      // Barely-valid baseline: same reading, weaker inputs.
      final weakBaseline = PersonalBaseline(
        type: HealthMetricType.heartRate,
        isEstablished: true,
        baselineValue: 68.0,
        minExpected: 60.0,
        maxExpected: 76.0,
        standardDeviation: 4.0,
        sampleCount: 5,
        confidence: 0.70,
        statusMessage: 'Baseline',
        calculatedAt: now,
      );
      final weak = engine.evaluate(
        measurement: hrMeasurement(85.0, quality: 0.65),
        baseline: weakBaseline,
        activity: restingActivity,
        referenceTime: now,
      );

      expect(strong.confidence, greaterThan(weak.confidence));
      expect(strong.confidence, greaterThan(0.80));
      expect(weak.confidence, lessThan(0.50));
    });

    test('language is non-diagnostic: headline and message use '
        '"worth monitoring" framing, never medical claims', () {
      final result = engine.evaluate(
        measurement: hrMeasurement(110.0),
        baseline: hrBaseline,
        activity: restingActivity,
        referenceTime: now,
      );

      expect(
        result.headline.toLowerCase().contains('unusual') ||
            result.headline.toLowerCase().contains('deviation'),
        isTrue,
      );
      expect(result.message.toLowerCase(), contains('worth monitoring'));
      for (final banned in [
        'diagnos', 'disease', 'you have', 'detected a', 'guaranteed', 'proves',
      ]) {
        expect(result.message.toLowerCase(), isNot(contains(banned)));
      }
    });
  });
}
