import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../analytics/activity_classifier.dart';
import '../../analytics/anomaly_engine.dart';
import '../../analytics/personal_baseline_engine.dart';
import '../../analytics/trend_engine.dart';
import '../../data/models/health_measurement.dart';
import '../../data/models/health_metric_type.dart';
import '../../data/repositories/health_repository_provider.dart';

/// The most recent measurement of a given [HealthMetricType], or null if
/// none is available yet. Re-evaluates reactively upon new incoming sensor readings.
final latestMeasurementProvider =
    StreamProvider.family<HealthMeasurement?, HealthMetricType>((
      ref,
      type,
    ) {
      final repository = ref.watch(healthRepositoryProvider);
      return repository.watchLatestMeasurement(type);
    });

/// Recent measurement history for a given [HealthMetricType], newest first.
/// Re-evaluates reactively upon new incoming sensor readings.
final measurementHistoryProvider =
    StreamProvider.family<List<HealthMeasurement>, HealthMetricType>((
      ref,
      type,
    ) {
      final repository = ref.watch(healthRepositoryProvider);
      return repository.watchMeasurementHistory(type);
    });

/// Real-time Activity Context Classification Provider.
///
/// Reactively evaluates the user's physical activity state by fusing
/// the latest heart rate measurement, step history cadence, and M8 data quality scores.
final activityClassificationProvider = Provider<ActivityClassificationResult>((ref) {
  final heartRateAsync = ref.watch(latestMeasurementProvider(HealthMetricType.heartRate));
  final stepsHistoryAsync = ref.watch(measurementHistoryProvider(HealthMetricType.steps));

  const classifier = ActivityClassifier();

  final hr = heartRateAsync.value;
  final stepsHistory = stepsHistoryAsync.value ?? const [];

  return classifier.classify(
    latestHeartRate: hr,
    recentSteps: stepsHistory,
  );
});

/// Personal Baseline Provider for a given [HealthMetricType].
///
/// Reactively evaluates historical measurements to compute individualized
/// baselines and normal expected ranges.
final personalBaselineProvider =
    Provider.family<PersonalBaseline, HealthMetricType>((ref, type) {
      final historyAsync = ref.watch(measurementHistoryProvider(type));
      final history = historyAsync.value ?? const [];

      const engine = PersonalBaselineEngine();
      return engine.computeBaseline(type, history);
    });

/// M11 trend lookback window per metric, mirroring [TrendEngine]:
/// HR & Steps: 7 days (daily aggregates), SpO2: 14 days (sparse spot checks).
Duration trendWindowFor(HealthMetricType type) {
  switch (type) {
    case HealthMetricType.heartRate:
      return TrendEngine.hrWindow;
    case HealthMetricType.steps:
      return TrendEngine.stepsWindow;
    case HealthMetricType.spo2:
      return TrendEngine.spo2Window;
  }
}

/// Historical measurements spanning the full M11 trend window for [type],
/// queried from local persistence via time-range filters.
///
/// Re-queries at most once per minute as new sensor readings arrive (trend
/// points are day-granular, so per-reading refreshes would only waste DB I/O).
final trendHistoryProvider =
    FutureProvider.family<List<HealthMeasurement>, HealthMetricType>((
      ref,
      type,
    ) async {
      final repository = ref.watch(healthRepositoryProvider);

      // Reactivity throttle: rebuild when the latest reading's minute changes.
      ref.watch(
        latestMeasurementProvider(type).select((async) {
          final t = async.value?.timestamp;
          return t == null ? 0 : t.millisecondsSinceEpoch ~/ 60000;
        }),
      );

      final now = DateTime.now();
      final windowStart = now.subtract(trendWindowFor(type));
      return repository.getMeasurementsInRange(
        type,
        startTime: windowStart,
        endTime: now,
      );
    });

/// Trend Analysis Provider for a given [HealthMetricType].
///
/// Evaluates moving statistics, rolling standard deviation, Z-score, slope,
/// and repeated deviations across the M11 trend window against the
/// established [personalBaselineProvider].
final metricTrendProvider =
    FutureProvider.family<MetricTrend, HealthMetricType>((ref, type) async {
      final history = await ref.watch(trendHistoryProvider(type).future);
      final baseline = ref.watch(personalBaselineProvider(type));

      const engine = TrendEngine();
      return engine.analyzeTrend(
        type: type,
        history: history,
        baseline: baseline,
      );
    });

/// Anomaly Detection Provider (M12) for a given [HealthMetricType].
///
/// A pure combination layer: fuses the latest M8-quality-enriched reading,
/// the M10 personal baseline, the M11 trend classification, and the M9
/// activity context into an [AnomalyResult] — recomputing none of them.
///
/// Anomaly semantics are per-new-reading, so this folds over the live
/// measurement stream, carrying the previous result in the closure for
/// ongoing-vs-new anomaly identity (`isOngoing` / `firstDetectedAt` — the
/// hook future M16 notification throttling will consume).
///
/// Performance: it re-evaluates only when a new reading arrives for this
/// metric (the same cadence the dashboard already renders at), and it
/// reads the trend/baseline/activity values already maintained by other
/// providers — no extra DB queries, no recomputation on the UI frame.
final anomalyProvider =
    StreamProvider.family<AnomalyResult, HealthMetricType>((ref, type) {
      final repository = ref.watch(healthRepositoryProvider);
      const engine = AnomalyEngine();

      return repository.watchLatestMeasurement(type).map((measurement) {
        // Read-only dependencies, resolved at evaluation time so a
        // low-quality reading is never judged against stale context.
        final baseline = ref.read(personalBaselineProvider(type));
        final activity = ref.read(activityClassificationProvider);
        final trend = ref.read(metricTrendProvider(type)).value;

        final previous = _previousAnomaly[type];
        final result = engine.evaluate(
          measurement: measurement,
          baseline: baseline,
          trend: trend,
          activity: activity,
          previous: previous,
        );
        if (result.isAnomaly) {
          _previousAnomaly[type] = result;
        } else {
          _previousAnomaly.remove(type);
        }
        return result;
      });
    });

/// Carries the last anomaly per metric for ongoing-vs-new identity.
/// Session-scoped state living beside the provider that owns it.
final Map<HealthMetricType, AnomalyResult> _previousAnomaly = {};
