import 'package:flutter_test/flutter_test.dart';
import 'package:vitalsync/analytics/personal_baseline_engine.dart';
import 'package:vitalsync/analytics/trend_engine.dart';
import 'package:vitalsync/data/models/activity_state.dart';
import 'package:vitalsync/data/models/health_data_source.dart';
import 'package:vitalsync/data/models/health_measurement.dart';
import 'package:vitalsync/data/models/health_metric_type.dart';

void main() {
  const engine = TrendEngine();
  final now = DateTime(2026, 9, 1, 12, 0, 0);

  group('TrendEngine - Data & Baseline Gating', () {
    test('returns insufficientData when baseline is not established', () {
      final unestablishedBaseline = PersonalBaseline(
        type: HealthMetricType.heartRate,
        isEstablished: false,
        sampleCount: 2,
        confidence: 0.2,
        statusMessage: 'Need more data',
        calculatedAt: now,
      );

      final trend = engine.analyzeTrend(
        type: HealthMetricType.heartRate,
        history: [],
        baseline: unestablishedBaseline,
        referenceTime: now,
      );

      expect(trend.direction, equals(TrendDirection.insufficientData));
      expect(trend.confidence, equals(0.0));
      expect(trend.factors, contains('unestablished_baseline'));
    });

    test('returns insufficientData when history spans fewer than minimum required days', () {
      final establishedBaseline = PersonalBaseline(
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

      // Only 2 days of HR data (minHrDays is 3)
      final history = [
        HealthMeasurement(
          id: 'hr_1',
          userId: 'u1',
          type: HealthMetricType.heartRate,
          value: 68.0,
          unit: 'bpm',
          timestamp: now.subtract(const Duration(days: 0, hours: 2)),
          source: HealthDataSource.galaxyWatch,
          activityState: ActivityState.resting,
        ),
        HealthMeasurement(
          id: 'hr_2',
          userId: 'u1',
          type: HealthMetricType.heartRate,
          value: 69.0,
          unit: 'bpm',
          timestamp: now.subtract(const Duration(days: 1, hours: 2)),
          source: HealthDataSource.galaxyWatch,
          activityState: ActivityState.resting,
        ),
      ];

      final trend = engine.analyzeTrend(
        type: HealthMetricType.heartRate,
        history: history,
        baseline: establishedBaseline,
        referenceTime: now,
      );

      expect(trend.direction, equals(TrendDirection.insufficientData));
      expect(trend.sampleCount, equals(2));
      expect(trend.factors.any((f) => f.startsWith('insufficient_trend_points')), isTrue);
    });
  });

  group('TrendEngine - Quality Filtering & Gating', () {
    final establishedBaseline = PersonalBaseline(
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

    test('excludes samples with quality < 0.60 and discounts confidence for noisy data', () {
      // 5 days of data, but day 3, 4, 5 have quality < 0.60
      final history = <HealthMeasurement>[];
      for (var day = 0; day < 5; day++) {
        history.add(
          HealthMeasurement(
            id: 'hr_$day',
            userId: 'u1',
            type: HealthMetricType.heartRate,
            value: 68.0,
            unit: 'bpm',
            timestamp: now.subtract(Duration(days: day, hours: 1)),
            source: HealthDataSource.galaxyWatch,
            activityState: ActivityState.resting,
            qualityScore: day < 2 ? 0.95 : 0.40, // 3 low-quality days dropped
          ),
        );
      }

      final trend = engine.analyzeTrend(
        type: HealthMetricType.heartRate,
        history: history,
        baseline: establishedBaseline,
        referenceTime: now,
      );

      // Only 2 days survived quality filtering -> falls back to insufficientData
      expect(trend.direction, equals(TrendDirection.insufficientData));
      expect(trend.sampleCount, equals(2));
    });
  });

  group('TrendEngine - Heart Rate Multi-Day Trends', () {
    final establishedBaseline = PersonalBaseline(
      type: HealthMetricType.heartRate,
      isEstablished: true,
      baselineValue: 68.0,
      minExpected: 60.0,
      maxExpected: 76.0,
      standardDeviation: 4.0,
      sampleCount: 25,
      confidence: 0.95,
      statusMessage: 'Typical resting baseline: 68 bpm',
      calculatedAt: now,
    );

    test('detects stable trend with resting daily medians matching baseline', () {
      // 5 days of resting HR: 67, 69, 68, 68, 67
      final history = [67.0, 69.0, 68.0, 68.0, 67.0].asMap().entries.map((e) {
        return HealthMeasurement(
          id: 'hr_${e.key}',
          userId: 'u1',
          type: HealthMetricType.heartRate,
          value: e.value,
          unit: 'bpm',
          timestamp: now.subtract(Duration(days: e.key, hours: 2)),
          source: HealthDataSource.galaxyWatch,
          activityState: ActivityState.resting,
          qualityScore: 0.95,
          confidence: 0.95,
        );
      }).toList();

      final trend = engine.analyzeTrend(
        type: HealthMetricType.heartRate,
        history: history,
        baseline: establishedBaseline,
        referenceTime: now,
      );

      expect(trend.direction, equals(TrendDirection.stable));
      expect(trend.zScore?.abs(), lessThan(1.0));
      expect(trend.rollingStandardDeviation, isNotNull);
      expect(trend.headline, contains('is stable'));
      expect(trend.confidence, greaterThanOrEqualTo(0.85));
      expect(trend.windowDays, equals(7));
    });

    test('detects elevated increasing trend when resting HR rises (+1.5 Z-score)', () {
      // 5 days of resting HR gradually rising: 70, 72, 74, 75, 76
      final history = [76.0, 75.0, 74.0, 72.0, 70.0].asMap().entries.map((e) {
        return HealthMeasurement(
          id: 'hr_${e.key}',
          userId: 'u1',
          type: HealthMetricType.heartRate,
          value: e.value,
          unit: 'bpm',
          timestamp: now.subtract(Duration(days: e.key, hours: 3)),
          source: HealthDataSource.galaxyWatch,
          activityState: ActivityState.resting,
          qualityScore: 0.95,
        );
      }).toList();

      final trend = engine.analyzeTrend(
        type: HealthMetricType.heartRate,
        history: history,
        baseline: establishedBaseline,
        referenceTime: now,
      );

      expect(trend.direction, equals(TrendDirection.increasing));
      expect(trend.zScore, greaterThan(1.25));
      expect(trend.slope, greaterThan(0.0));
      expect(trend.headline, contains('trending higher'));
    });

    test('detects decreasing trend when resting HR is consistently low', () {
      // 5 days of resting HR: 60, 61, 60, 61, 60
      final history = [60.0, 61.0, 60.0, 61.0, 60.0].asMap().entries.map((e) {
        return HealthMeasurement(
          id: 'hr_${e.key}',
          userId: 'u1',
          type: HealthMetricType.heartRate,
          value: e.value,
          unit: 'bpm',
          timestamp: now.subtract(Duration(days: e.key, hours: 3)),
          source: HealthDataSource.galaxyWatch,
          activityState: ActivityState.resting,
          qualityScore: 0.95,
        );
      }).toList();

      final trend = engine.analyzeTrend(
        type: HealthMetricType.heartRate,
        history: history,
        baseline: establishedBaseline,
        referenceTime: now,
      );

      expect(trend.direction, equals(TrendDirection.decreasing));
      expect(trend.zScore, lessThan(-1.25));
      expect(trend.headline, contains('trending lower'));
    });

    test('detects acute sudden shift when Z-score exceeds 2.2', () {
      // 4 days with a sharp sustained jump to 80+ bpm
      final history = [82.0, 83.0, 81.0, 82.0].asMap().entries.map((e) {
        return HealthMeasurement(
          id: 'hr_${e.key}',
          userId: 'u1',
          type: HealthMetricType.heartRate,
          value: e.value,
          unit: 'bpm',
          timestamp: now.subtract(Duration(days: e.key, hours: 2)),
          source: HealthDataSource.galaxyWatch,
          activityState: ActivityState.resting,
          qualityScore: 1.0,
        );
      }).toList();

      final trend = engine.analyzeTrend(
        type: HealthMetricType.heartRate,
        history: history,
        baseline: establishedBaseline,
        referenceTime: now,
      );

      expect(trend.direction, equals(TrendDirection.suddenShift));
      expect(trend.zScore, greaterThanOrEqualTo(2.2));
      expect(trend.headline, contains('Acute elevation detected'));
      expect(trend.message, contains('Worth monitoring if sustained'));
    });

    test('detects repeated deviations when values swing outside expected range', () {
      // minExpected=60, maxExpected=76
      // Days: 80 (high), 56 (low), 78 (high), 68 (normal), 57 (low)
      final history = [57.0, 68.0, 78.0, 56.0, 80.0].asMap().entries.map((e) {
        return HealthMeasurement(
          id: 'hr_${e.key}',
          userId: 'u1',
          type: HealthMetricType.heartRate,
          value: e.value,
          unit: 'bpm',
          timestamp: now.subtract(Duration(days: e.key, hours: 2)),
          source: HealthDataSource.galaxyWatch,
          activityState: ActivityState.resting,
          qualityScore: 0.95,
        );
      }).toList();

      final trend = engine.analyzeTrend(
        type: HealthMetricType.heartRate,
        history: history,
        baseline: establishedBaseline,
        referenceTime: now,
      );

      expect(trend.direction, equals(TrendDirection.repeatedDeviation));
      expect(trend.headline, contains('Fluctuating readings detected'));
      expect(trend.factors, contains('repeated_range_deviations'));
    });

    test('ignores active/exercise heart rate readings when computing resting trend', () {
      // 4 days: Resting HR is 68 each day, but each day also has a 145 bpm workout
      final history = <HealthMeasurement>[];
      for (var day = 0; day < 4; day++) {
        // Resting sample
        history.add(
          HealthMeasurement(
            id: 'hr_rest_$day',
            userId: 'u1',
            type: HealthMetricType.heartRate,
            value: 68.0,
            unit: 'bpm',
            timestamp: now.subtract(Duration(days: day, hours: 4)),
            source: HealthDataSource.galaxyWatch,
            activityState: ActivityState.resting,
            qualityScore: 0.95,
          ),
        );
        // Active exercise sample
        history.add(
          HealthMeasurement(
            id: 'hr_active_$day',
            userId: 'u1',
            type: HealthMetricType.heartRate,
            value: 145.0,
            unit: 'bpm',
            timestamp: now.subtract(Duration(days: day, hours: 2)),
            source: HealthDataSource.galaxyWatch,
            activityState: ActivityState.exercising,
            qualityScore: 0.95,
          ),
        );
      }

      final trend = engine.analyzeTrend(
        type: HealthMetricType.heartRate,
        history: history,
        baseline: establishedBaseline,
        referenceTime: now,
      );

      // The 145 bpm workouts should not skew the resting trend to increasing/suddenShift
      expect(trend.direction, equals(TrendDirection.stable));
      expect(trend.recentAverage, closeTo(68.0, 1.0));
    });
  });

  group('TrendEngine - Steps Multi-Day Trends', () {
    final establishedBaseline = PersonalBaseline(
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

    test('detects stable steps trend with daily totals matching baseline', () {
      // 5 days of cumulative step counters: ~7000/day
      final history = <HealthMeasurement>[];
      for (var day = 0; day < 5; day++) {
        history.add(
          HealthMeasurement(
            id: 'steps_$day',
            userId: 'u1',
            type: HealthMetricType.steps,
            value: 7200.0,
            unit: 'steps',
            timestamp: now.subtract(Duration(days: day, hours: 1)),
            source: HealthDataSource.galaxyWatch,
            qualityScore: 0.95,
          ),
        );
      }

      final trend = engine.analyzeTrend(
        type: HealthMetricType.steps,
        history: history,
        baseline: establishedBaseline,
        referenceTime: now,
      );

      expect(trend.direction, equals(TrendDirection.stable));
      expect(trend.recentAverage, equals(7200.0));
      expect(trend.headline, contains('is stable'));
    });

    test('detects elevated steps trend when activity increases (+25%)', () {
      final history = [9500.0, 9800.0, 9200.0, 9600.0].asMap().entries.map((e) {
        return HealthMeasurement(
          id: 'steps_${e.key}',
          userId: 'u1',
          type: HealthMetricType.steps,
          value: e.value,
          unit: 'steps',
          timestamp: now.subtract(Duration(days: e.key, hours: 2)),
          source: HealthDataSource.galaxyWatch,
          qualityScore: 0.95,
        );
      }).toList();

      final trend = engine.analyzeTrend(
        type: HealthMetricType.steps,
        history: history,
        baseline: establishedBaseline,
        referenceTime: now,
      );

      expect(trend.direction, equals(TrendDirection.increasing));
      expect(trend.zScore, greaterThan(1.2));
      expect(trend.headline, contains('trending higher'));
    });
  });

  group('TrendEngine - SpO2 14-Day Sparse Spot Check Trends', () {
    final establishedBaseline = PersonalBaseline(
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

    test('detects stable SpO2 across 14-day window spot checks', () {
      // 5 spot checks over 10 days: 98, 97, 98, 98, 97
      final history = [98.0, 97.0, 98.0, 98.0, 97.0].asMap().entries.map((e) {
        return HealthMeasurement(
          id: 'spo2_${e.key}',
          userId: 'u1',
          type: HealthMetricType.spo2,
          value: e.value,
          unit: '%',
          timestamp: now.subtract(Duration(days: e.key * 2, hours: 1)),
          source: HealthDataSource.galaxyWatch,
          qualityScore: 0.95,
        );
      }).toList();

      final trend = engine.analyzeTrend(
        type: HealthMetricType.spo2,
        history: history,
        baseline: establishedBaseline,
        referenceTime: now,
      );

      expect(trend.direction, equals(TrendDirection.stable));
      expect(trend.windowDays, equals(14));
      expect(trend.recentAverage, closeTo(97.6, 0.2));
      expect(trend.headline, contains('is stable'));
    });

    test('detects acute drop in SpO2 spot checks', () {
      // 3 spot checks with values falling to 92-93%
      final history = [92.0, 93.0, 92.0].asMap().entries.map((e) {
        return HealthMeasurement(
          id: 'spo2_${e.key}',
          userId: 'u1',
          type: HealthMetricType.spo2,
          value: e.value,
          unit: '%',
          timestamp: now.subtract(Duration(days: e.key, hours: 2)),
          source: HealthDataSource.galaxyWatch,
          qualityScore: 0.95,
        );
      }).toList();

      final trend = engine.analyzeTrend(
        type: HealthMetricType.spo2,
        history: history,
        baseline: establishedBaseline,
        referenceTime: now,
      );

      expect(trend.direction, equals(TrendDirection.suddenShift));
      expect(trend.headline, contains('Notable drop detected'));
    });
  });
}
