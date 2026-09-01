import '../data/models/activity_state.dart';
import '../data/models/health_measurement.dart';
import '../data/models/health_metric_type.dart';
import 'activity_classifier.dart';
import 'personal_baseline_engine.dart';
import 'trend_engine.dart';

/// Explainable severity scale for a detected anomaly.
///
/// Driven by how far the reading sits beyond the nearest bound of the
/// user's M10 expected range, expressed in units of that range's half-width
/// (the "deviation ratio"):
/// - [none]: within the expected range (not an anomaly).
/// - [mild]: beyond a bound by up to 25% of the range half-width.
/// - [moderate]: beyond a bound by 25%–75% of the range half-width.
/// - [severe]: beyond a bound by more than 75% of the range half-width.
///
/// A reading already flagged by M11 as part of a `suddenShift` or
/// `repeatedDeviation` pattern is escalated one level: a sustained,
/// statistically confirmed pattern is a different situation than an
/// isolated one-off blip.
enum AnomalySeverity {
  none,
  mild,
  moderate,
  severe;

  String get label {
    switch (this) {
      case AnomalySeverity.none:
        return 'Within range';
      case AnomalySeverity.mild:
        return 'Slightly unusual';
      case AnomalySeverity.moderate:
        return 'Unusual pattern';
      case AnomalySeverity.severe:
        return 'Notable deviation';
    }
  }
}

/// Result of a single anomaly evaluation for one measurement.
///
/// Output shape per the M12 design:
/// `{ isAnomaly, severity, deviation, confidence }` — plus the
/// ongoing-vs-new identity fields (`anomalyKey`, `isOngoing`,
/// `firstDetectedAt`) that future M16 notification throttling will consume
/// to treat a sustained condition as one ongoing anomaly rather than a
/// fresh alert on every new sample.
class AnomalyResult {
  const AnomalyResult({
    required this.type,
    required this.isAnomaly,
    required this.severity,
    required this.confidence,
    required this.headline,
    required this.message,
    required this.reasons,
    required this.anomalyKey,
    required this.isOngoing,
    required this.firstDetectedAt,
    required this.detectedAt,
    this.deviation,
  }) : assert(
         confidence >= 0.0 && confidence <= 1.0,
         'confidence must be between 0.0 and 1.0',
       );

  /// Not-anomaly result used when gating suppresses classification
  /// (low quality, unestablished baseline, stale reading, no data).
  factory AnomalyResult.gated(
    HealthMetricType type, {
    required DateTime detectedAt,
    required List<String> reasons,
  }) {
    return AnomalyResult(
      type: type,
      isAnomaly: false,
      severity: AnomalySeverity.none,
      confidence: 0.0,
      headline: '',
      message: '',
      reasons: reasons,
      anomalyKey: '',
      isOngoing: false,
      firstDetectedAt: detectedAt,
      detectedAt: detectedAt,
    );
  }

  final HealthMetricType type;

  /// Whether this evaluation concluded the reading is an unusual pattern
  /// worth surfacing. Never true when quality or baseline gating failed.
  final bool isAnomaly;

  final AnomalySeverity severity;

  /// Signed distance beyond the nearest expected-range bound, in the
  /// metric's own units (e.g. +14.0 bpm above the upper bound). Null when
  /// not an anomaly or when the verdict came from the trend-pattern path.
  final double? deviation;

  /// 0.0 to 1.0 combined confidence across the supporting inputs:
  /// current reading M8 quality, M10 baseline confidence, and M11 trend
  /// confidence when the trend contributed to the verdict. An anomaly
  /// built on a barely-valid baseline reports lower confidence than one
  /// built on a well-established one.
  final double confidence;

  /// Plain-language, non-diagnostic headline (empty when not an anomaly).
  final String headline;

  /// Plain-language, non-diagnostic explanation (empty when not an anomaly).
  final String message;

  /// Explainable machine-readable reasons behind the verdict.
  final List<String> reasons;

  /// Stable identity of the anomaly for ongoing-vs-new deduplication:
  /// `<metric>:<high|low>[:pattern]`. Two evaluations with the same key
  /// within the continuity window describe the same ongoing anomaly.
  final String anomalyKey;

  /// True when the previous evaluation already flagged this same
  /// [anomalyKey] recently — i.e. this is a continuation, not a new one.
  final bool isOngoing;

  /// When this [anomalyKey] was first observed (carried forward from the
  /// previous evaluation while [isOngoing] is true).
  final DateTime firstDetectedAt;

  /// Timestamp of the measurement this evaluation ran against.
  final DateTime detectedAt;

  @override
  String toString() =>
      'AnomalyResult(type: ${type.name}, isAnomaly: $isAnomaly, '
      'severity: ${severity.label}, deviation: ${deviation?.toStringAsFixed(1) ?? "N/A"}, '
      'confidence: ${(confidence * 100).toStringAsFixed(0)}%, '
      'key: $anomalyKey, ongoing: $isOngoing)';
}

/// Anomaly Detection Engine for VitalSync biometrics (M12).
///
/// A pure combination/decision layer over the existing M8–M11 outputs — it
/// re-derives none of them:
/// - M8: the current measurement's quality score (already enriched by
///   [DataQualityEngine] at ingestion).
/// - M9: the current [ActivityClassificationResult] activity context.
/// - M10: the established [PersonalBaseline] with expected range.
/// - M11: the current [MetricTrend] classification and confidence.
///
/// Core safety rule, structurally enforced: **quality gate first, always.**
/// [evaluate] checks M8 quality before any deviation math exists in scope —
/// a low-quality reading can never be classified as an anomaly, no matter
/// how extreme its value looks.
///
/// Zero synthetic backfill: with no measurement, no established baseline,
/// or insufficient quality, the verdict is "not an anomaly — insufficient
/// data/quality", which is always an acceptable and often correct output.
class AnomalyEngine {
  const AnomalyEngine();

  /// Minimum M8 quality score for a reading to be eligible for anomaly
  /// classification at all. Matches the M10/M11 inclusion threshold (0.60):
  /// a reading too unreliable to define "normal" is too unreliable to be
  /// judged against it.
  static const double minQualityThreshold = 0.60;

  /// M11 trend confidence required for the trend classification to
  /// escalate severity or, alone, drive a pattern anomaly.
  static const double minTrendConfidence = 0.50;

  /// Two evaluations of the same [AnomalyResult.anomalyKey] within this
  /// window are treated as one ongoing anomaly ([AnomalyResult.firstDetectedAt]
  /// carries forward). Future M16 notification throttling consumes this.
  static const Duration ongoingContinuityWindow = Duration(hours: 6);

  /// Maximum age of a measurement to be evaluated as "current".
  static const Duration maxMeasurementAge = Duration(minutes: 10);

  /// Evaluates a single measurement for anomalous behavior.
  ///
  /// [measurement]: The current reading (M8-enriched). Null yields a gated
  ///   not-anomaly result.
  /// [baseline]: The user's M10 personal baseline.
  /// [trend]: The current M11 trend, or null when trend analysis is
  ///   unavailable (e.g. storage error) — detection degrades gracefully to
  ///   baseline-only evaluation.
  /// [activity]: The current M9 activity classification.
  /// [previous]: The previous evaluation's result for this metric, used to
  ///   distinguish an ongoing anomaly from a newly-detected one. Null for
  ///   the first evaluation.
  /// [referenceTime]: Clock reference (defaults to [DateTime.now]).
  AnomalyResult evaluate({
    required HealthMeasurement? measurement,
    required PersonalBaseline baseline,
    MetricTrend? trend,
    required ActivityClassificationResult activity,
    AnomalyResult? previous,
    DateTime? referenceTime,
  }) {
    final now = referenceTime ?? DateTime.now();

    // ------------------------------------------------------------------
    // GATE 1 (structural, first, always): M8 data quality.
    // No deviation math exists in scope above this line — a low-quality
    // reading can never be classified as an anomaly by any code path.
    // ------------------------------------------------------------------
    if (measurement == null) {
      return AnomalyResult.gated(
        baseline.type,
        detectedAt: now,
        reasons: const ['no_measurement_available'],
      );
    }

    final type = measurement.type;
    final quality = measurement.qualityScore ?? 1.0;

    if (quality < minQualityThreshold) {
      return AnomalyResult.gated(
        type,
        detectedAt: measurement.timestamp,
        reasons: [
          'quality_gate_blocked',
          'quality_${(quality * 100).toStringAsFixed(0)}%',
          'low_quality_reading_not_anomaly',
        ],
      );
    }

    // ------------------------------------------------------------------
    // GATE 2: M10 baseline validity + measurement recency.
    // An anomaly is a deviation from *this user's* expected range; without
    // an established baseline there is nothing to deviate from, and a
    // stale measurement says nothing about the present.
    // ------------------------------------------------------------------
    final isFresh =
        now.difference(measurement.timestamp).abs() <= maxMeasurementAge;
    if (!baseline.isEstablished ||
        baseline.baselineValue == null ||
        baseline.minExpected == null ||
        baseline.maxExpected == null ||
        !isFresh) {
      return AnomalyResult.gated(
        type,
        detectedAt: measurement.timestamp,
        reasons: [
          if (!baseline.isEstablished) 'baseline_not_established',
          if (baseline.isEstablished &&
              (baseline.baselineValue == null ||
                  baseline.minExpected == null ||
                  baseline.maxExpected == null))
            'baseline_range_missing',
          if (!isFresh) 'measurement_stale',
        ],
      );
    }

    final minExpected = baseline.minExpected!;
    final maxExpected = baseline.maxExpected!;
    final unit = measurement.unit;
    final reasons = <String>[
      'quality_${(quality * 100).toStringAsFixed(0)}%',
      'baseline_${baseline.baselineValue!.toStringAsFixed(1)}',
      'expected_range_${minExpected.toStringAsFixed(0)}_${maxExpected.toStringAsFixed(0)}',
    ];

    // ------------------------------------------------------------------
    // Point deviation vs. the M10 expected range.
    //
    // Steps arrive as cumulative counter / interval bucket values, which
    // are not point-comparable to a *daily total* baseline — a mid-morning
    // cumulative count says nothing about the day. The point-deviation
    // check is therefore skipped for steps; step anomalies surface only
    // via the M11 trend-pattern path below.
    // ------------------------------------------------------------------
    double? distanceBeyondBound;
    bool? isHighSide;
    if (type != HealthMetricType.steps) {
      if (measurement.value > maxExpected) {
        distanceBeyondBound = measurement.value - maxExpected;
        isHighSide = true;
      } else if (measurement.value < minExpected) {
        distanceBeyondBound = minExpected - measurement.value;
        isHighSide = false;
      }
    }

    // ------------------------------------------------------------------
    // GATE 3: M9 activity context suppression.
    // Elevated heart rate while walking/active/exercising is expected
    // physiology, not an anomaly — the M9 classification explains it.
    // (Only high-side deviations can be activity-explained.)
    // ------------------------------------------------------------------
    if (distanceBeyondBound != null &&
        isHighSide == true &&
        _activityExplainsElevation(type, activity)) {
      reasons.add('elevation_explained_by_activity_${activity.state.name}');
      return AnomalyResult.gated(
        type,
        detectedAt: measurement.timestamp,
        reasons: reasons,
      );
    }

    // ------------------------------------------------------------------
    // M11 trend corroboration: a statistically confirmed sustained pattern
    // (suddenShift / repeatedDeviation) changes the situation from an
    // isolated one-off blip to part of an established pattern.
    // ------------------------------------------------------------------
    final trendIsEstablishedPattern = trend != null &&
        (trend.direction == TrendDirection.suddenShift ||
            trend.direction == TrendDirection.repeatedDeviation) &&
        trend.confidence >= minTrendConfidence;

    final double deviationRatio;
    final bool isHigh;
    if (distanceBeyondBound != null) {
      // Primary path: the reading itself sits beyond the expected range.
      deviationRatio = _deviationRatio(distanceBeyondBound, baseline);
      isHigh = isHighSide!;
      reasons.add('outside_expected_range');
      reasons.add('deviation_${isHigh ? "+" : "-"}${distanceBeyondBound.toStringAsFixed(1)}_$unit');
      reasons.add(trendIsEstablishedPattern
          ? 'part_of_confirmed_${trend.direction.name}_pattern'
          : 'isolated_deviation');
    } else if (trendIsEstablishedPattern) {
      // No single-reading deviation (or steps, where point comparison is
      // invalid), but M11 holds a confirmed acute/repeated pattern —
      // surface it as a pattern anomaly.
      deviationRatio = _severityRatioFromTrendZScore(trend);
      isHigh = (trend.zScore ?? 0) >= 0;
      reasons.add('trend_confirmed_${trend.direction.name}_pattern');
    } else {
      // Within range, no confirmed pattern: normal.
      reasons.add('within_expected_range');
      return AnomalyResult.gated(
        type,
        detectedAt: measurement.timestamp,
        reasons: reasons,
      );
    }

    final severity =
        _classifySeverity(deviationRatio, trendIsEstablishedPattern);

    // Confidence combines the supporting inputs: current reading quality,
    // baseline validity, and M11 trend confidence when it contributed.
    final trendFactor =
        trendIsEstablishedPattern ? trend.confidence : 1.0;
    final confidence =
        (quality * baseline.confidence * (0.5 + 0.5 * trendFactor))
            .clamp(0.0, 1.0);

    final anomalyKey = '${type.name}:${isHigh ? 'high' : 'low'}'
        '${trendIsEstablishedPattern ? ':pattern' : ''}';

    final (headline, message) = _describe(
      type: type,
      measurement: measurement,
      severity: severity,
      isHigh: isHigh,
      trend: trendIsEstablishedPattern ? trend : null,
      minExpected: minExpected,
      maxExpected: maxExpected,
      unit: unit,
    );

    // ------------------------------------------------------------------
    // Ongoing vs. new: same anomalyKey as the previous evaluation within
    // the continuity window => same ongoing anomaly, not a fresh one.
    // firstDetectedAt carries forward so M16 can throttle on duration.
    // ------------------------------------------------------------------
    final isOngoing = previous != null &&
        previous.isAnomaly &&
        previous.anomalyKey == anomalyKey &&
        now.difference(previous.detectedAt).abs() <= ongoingContinuityWindow;
    if (isOngoing) {
      reasons.add('ongoing_anomaly_continuation');
    }

    return AnomalyResult(
      type: type,
      isAnomaly: true,
      severity: severity,
      deviation: distanceBeyondBound != null
          ? double.parse(
              ((isHigh ? 1 : -1) * distanceBeyondBound).toStringAsFixed(1),
            )
          : null,
      confidence: double.parse(confidence.toStringAsFixed(2)),
      headline: headline,
      message: message,
      reasons: reasons,
      anomalyKey: anomalyKey,
      isOngoing: isOngoing,
      firstDetectedAt:
          isOngoing ? previous.firstDetectedAt : measurement.timestamp,
      detectedAt: measurement.timestamp,
    );
  }

  /// Whether the current M9 activity classification already explains an
  /// elevated reading. Only *high*-side deviation can be activity-explained,
  /// and only for heart rate (elevation during movement is expected
  /// physiology). SpO2 expectations do not shift with activity at this
  /// granularity; steps never reach point-deviation evaluation.
  bool _activityExplainsElevation(
    HealthMetricType type,
    ActivityClassificationResult activity,
  ) {
    if (type != HealthMetricType.heartRate) return false;
    return activity.state == ActivityState.exercising ||
        activity.state == ActivityState.active ||
        activity.state == ActivityState.walking;
  }

  /// Deviation expressed in units of the expected range's half-width, so
  /// the severity scale means the same thing across metrics with wildly
  /// different absolute scales (bpm vs. % vs. steps).
  ///
  /// Rationale for the thresholds (documented, not arbitrary):
  /// - M10 builds ranges at roughly median ± 1.5σ, so the half-width *is*
  ///   the user's normal margin. A reading 25% of that margin beyond the
  ///   bound (~1.9σ from baseline) is a clear but small excursion (mild);
  ///   75% (~2.6σ) is substantial (moderate); beyond that the reading sits
  ///   further outside than the entire normal margin is wide (severe).
  double _deviationRatio(
    double distanceBeyondBound,
    PersonalBaseline baseline,
  ) {
    final halfWidth = (baseline.maxExpected! - baseline.minExpected!) / 2;
    if (halfWidth <= 0) {
      // Degenerate zero-width range: any excursion beyond it is substantial.
      return 1.0;
    }
    return distanceBeyondBound / halfWidth;
  }

  /// Maps an M11 trend Z-score onto the same deviation-ratio severity
  /// scale. M10 ranges sit at ≈1.5σ, so the excess of |Z| over the 1.5σ
  /// range edge, in 1.5σ half-width units, is the pattern's equivalent
  /// deviation ratio.
  double _severityRatioFromTrendZScore(MetricTrend trend) {
    final z = trend.zScore?.abs() ?? 0.0;
    return ((z - 1.5) / 1.5).clamp(0.05, 4.0);
  }

  AnomalySeverity _classifySeverity(
    double deviationRatio,
    bool trendIsEstablishedPattern,
  ) {
    AnomalySeverity severity;
    if (deviationRatio > 0.75) {
      severity = AnomalySeverity.severe;
    } else if (deviationRatio > 0.25) {
      severity = AnomalySeverity.moderate;
    } else {
      severity = AnomalySeverity.mild;
    }

    // A reading that is part of an M11-confirmed sustained pattern is a
    // different situation than an isolated blip — escalate one level.
    if (trendIsEstablishedPattern && severity != AnomalySeverity.severe) {
      severity = AnomalySeverity.values[severity.index + 1];
    }
    return severity;
  }

  (String, String) _describe({
    required HealthMetricType type,
    required HealthMeasurement measurement,
    required AnomalySeverity severity,
    required bool isHigh,
    required MetricTrend? trend,
    required double minExpected,
    required double maxExpected,
    required String unit,
  }) {
    final metricName = switch (type) {
      HealthMetricType.heartRate => 'heart rate',
      HealthMetricType.steps => 'activity',
      HealthMetricType.spo2 => 'blood oxygen',
    };
    final rangeText =
        '${minExpected.round()}–${maxExpected.round()} $unit';

    if (trend != null) {
      // Pattern-backed anomaly (M11 suddenShift / repeatedDeviation).
      final patternWord = trend.direction == TrendDirection.suddenShift
          ? 'a sustained shift'
          : 'recurring fluctuations';
      final headline = 'Unusual $metricName pattern';
      final message =
          'Your recent $metricName readings show $patternWord outside your '
          'usual range ($rangeText). Worth monitoring — this is an '
          'observation about your data, not a diagnosis.';
      return (headline, message);
    }

    final directionWord = isHigh ? 'above' : 'below';
    final headline = switch (severity) {
      AnomalySeverity.mild => 'Slightly unusual $metricName reading',
      AnomalySeverity.moderate => 'Unusual $metricName reading',
      AnomalySeverity.severe => 'Notable $metricName deviation',
      AnomalySeverity.none => '',
    };
    final message =
        'Your $metricName reading of ${measurement.value.round()} $unit is '
        '$directionWord your usual range ($rangeText). A single reading '
        'outside your usual range is often nothing — worth monitoring.';
    return (headline, message);
  }
}
