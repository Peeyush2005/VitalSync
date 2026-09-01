import 'dart:math';

import '../data/models/activity_state.dart';
import '../data/models/health_measurement.dart';
import '../data/models/health_metric_type.dart';

/// Result object representing a user's calculated personal baseline.
class PersonalBaseline {
  const PersonalBaseline({
    required this.type,
    required this.isEstablished,
    required this.sampleCount,
    required this.confidence,
    required this.statusMessage,
    required this.calculatedAt,
    this.baselineValue,
    this.minExpected,
    this.maxExpected,
    this.standardDeviation,
    this.activityContext,
  }) : assert(
         confidence >= 0.0 && confidence <= 1.0,
         'confidence must be between 0.0 and 1.0',
       );

  final HealthMetricType type;

  /// Whether enough high-quality history exists to establish a statistically valid baseline.
  /// If false, [baselineValue], [minExpected], and [maxExpected] are null.
  final bool isEstablished;

  /// Central tendency baseline value (median or robust mean).
  final double? baselineValue;

  /// Lower bound of the user's normal expected physiological range.
  final double? minExpected;

  /// Upper bound of the user's normal expected physiological range.
  final double? maxExpected;

  /// Standard deviation across baseline samples.
  final double? standardDeviation;

  /// Number of high-quality samples used to calculate this baseline.
  final int sampleCount;

  /// 0.0 to 1.0 confidence score based on sample count, time span, and signal stability.
  final double confidence;

  /// Plain-language description of the baseline status (never diagnostic).
  final String statusMessage;

  /// Optional activity context used for segmentation (e.g. [ActivityState.resting] for RHR).
  final ActivityState? activityContext;

  /// Timestamp when this baseline was computed.
  final DateTime calculatedAt;

  @override
  String toString() =>
      'PersonalBaseline(type: ${type.name}, established: $isEstablished, '
      'value: ${baselineValue?.toStringAsFixed(1) ?? "N/A"}, '
      'range: [${minExpected?.toStringAsFixed(1) ?? "N/A"} - ${maxExpected?.toStringAsFixed(1) ?? "N/A"}], '
      'samples: $sampleCount, confidence: ${(confidence * 100).toStringAsFixed(0)}%)';
}

/// Personal Baseline Engine for VitalSync biometrics.
///
/// Computes individualized physiological baselines and normal expected ranges
/// from historical measurements:
/// - Filters out low-M8-quality readings (< 0.60) and artifacts.
/// - Segments by M9 activity context (e.g. resting HR only uses Resting state).
/// - Strictly gates on minimum sample thresholds before establishing a baseline.
/// - Zero synthetic backfill: If data is insufficient, returns [isEstablished: false].
class PersonalBaselineEngine {
  const PersonalBaselineEngine();

  // Minimum sample thresholds to consider a baseline established
  static const int minHeartRateSamples = 5;
  static const int minStepsDailySamples = 3;
  static const int minSpo2Samples = 3;

  // Minimum required data quality score to be included in baseline calculation
  static const double minQualityThreshold = 0.60;

  /// Computes the personal baseline for a given [HealthMetricType] from [history].
  PersonalBaseline computeBaseline(
    HealthMetricType type,
    List<HealthMeasurement> history, {
    DateTime? referenceTime,
  }) {
    switch (type) {
      case HealthMetricType.heartRate:
        return computeRestingHeartRateBaseline(history, referenceTime: referenceTime);
      case HealthMetricType.steps:
        return computeDailyStepsBaseline(history, referenceTime: referenceTime);
      case HealthMetricType.spo2:
        return computeRestingSpO2Baseline(history, referenceTime: referenceTime);
    }
  }

  /// Computes Resting Heart Rate (RHR) baseline.
  ///
  /// Filters strictly for resting/low-motion measurements with high M8 quality.
  PersonalBaseline computeRestingHeartRateBaseline(
    List<HealthMeasurement> history, {
    DateTime? referenceTime,
  }) {
    final now = referenceTime ?? DateTime.now();

    // 1. Filter for valid resting HR samples with acceptable M8 quality
    final validSamples = history.where((m) {
      if (m.type != HealthMetricType.heartRate) return false;
      final quality = m.qualityScore ?? 1.0;
      if (quality < minQualityThreshold) return false;

      // Prefer explicit resting context; if activityState is null/unknown, only include if HR <= 90 BPM
      if (m.activityState != null) {
        return m.activityState == ActivityState.resting;
      }
      return m.value <= 90.0;
    }).toList();

    if (validSamples.length < minHeartRateSamples) {
      return PersonalBaseline(
        type: HealthMetricType.heartRate,
        isEstablished: false,
        sampleCount: validSamples.length,
        confidence: (validSamples.length / minHeartRateSamples) * 0.5,
        statusMessage: 'Need ${minHeartRateSamples - validSamples.length} more resting readings to establish your baseline',
        activityContext: ActivityState.resting,
        calculatedAt: now,
      );
    }

    // 2. Statistical calculations
    final values = validSamples.map((m) => m.value).toList()..sort();
    final median = _calculateMedian(values);
    final mean = values.reduce((a, b) => a + b) / values.length;
    final stdDev = _calculateStdDev(values, mean);

    // Expected resting range: median ± 1.5 sigma (bounded between 40 and 110 bpm)
    final margin = max(5.0, 1.5 * stdDev);
    final minExpected = max(40.0, median - margin);
    final maxExpected = min(110.0, median + margin);

    // Confidence scales with sample count up to 25 samples
    final confidence = min(1.0, 0.70 + (validSamples.length / 25.0) * 0.30);

    return PersonalBaseline(
      type: HealthMetricType.heartRate,
      isEstablished: true,
      baselineValue: double.parse(median.toStringAsFixed(1)),
      minExpected: double.parse(minExpected.toStringAsFixed(1)),
      maxExpected: double.parse(maxExpected.toStringAsFixed(1)),
      standardDeviation: double.parse(stdDev.toStringAsFixed(2)),
      sampleCount: validSamples.length,
      confidence: double.parse(confidence.toStringAsFixed(2)),
      statusMessage: 'Typical resting baseline: ${median.round()} bpm (expected ${minExpected.round()}–${maxExpected.round()} bpm)',
      activityContext: ActivityState.resting,
      calculatedAt: now,
    );
  }

  /// Computes Daily Steps Activity baseline.
  PersonalBaseline computeDailyStepsBaseline(
    List<HealthMeasurement> history, {
    DateTime? referenceTime,
  }) {
    final now = referenceTime ?? DateTime.now();

    final validSamples = history.where((m) {
      if (m.type != HealthMetricType.steps) return false;
      final quality = m.qualityScore ?? 1.0;
      return quality >= minQualityThreshold && m.value >= 0;
    }).toList();

    if (validSamples.length < minStepsDailySamples) {
      return PersonalBaseline(
        type: HealthMetricType.steps,
        isEstablished: false,
        sampleCount: validSamples.length,
        confidence: (validSamples.length / minStepsDailySamples) * 0.5,
        statusMessage: 'Need ${minStepsDailySamples - validSamples.length} more days of activity to establish step baseline',
        calculatedAt: now,
      );
    }

    final values = validSamples.map((m) => m.value).toList()..sort();
    final median = _calculateMedian(values);
    final mean = values.reduce((a, b) => a + b) / values.length;
    final stdDev = _calculateStdDev(values, mean);

    final minExpected = max(500.0, median - 1.2 * stdDev);
    final maxExpected = median + 1.5 * stdDev;

    final confidence = min(1.0, 0.70 + (validSamples.length / 14.0) * 0.30);

    return PersonalBaseline(
      type: HealthMetricType.steps,
      isEstablished: true,
      baselineValue: double.parse(median.toStringAsFixed(0)),
      minExpected: double.parse(minExpected.toStringAsFixed(0)),
      maxExpected: double.parse(maxExpected.toStringAsFixed(0)),
      standardDeviation: double.parse(stdDev.toStringAsFixed(1)),
      sampleCount: validSamples.length,
      confidence: double.parse(confidence.toStringAsFixed(2)),
      statusMessage: 'Daily activity baseline: ${median.toInt()} steps (range ${minExpected.toInt()}–${maxExpected.toInt()})',
      calculatedAt: now,
    );
  }

  /// Computes Resting Blood Oxygen (SpO2) baseline.
  PersonalBaseline computeRestingSpO2Baseline(
    List<HealthMeasurement> history, {
    DateTime? referenceTime,
  }) {
    final now = referenceTime ?? DateTime.now();

    final validSamples = history.where((m) {
      if (m.type != HealthMetricType.spo2) return false;
      final quality = m.qualityScore ?? 1.0;
      return quality >= 0.70 && m.value >= 85.0 && m.value <= 100.0;
    }).toList();

    if (validSamples.length < minSpo2Samples) {
      return PersonalBaseline(
        type: HealthMetricType.spo2,
        isEstablished: false,
        sampleCount: validSamples.length,
        confidence: (validSamples.length / minSpo2Samples) * 0.5,
        statusMessage: 'Need ${minSpo2Samples - validSamples.length} more SpO2 spot checks to establish baseline',
        calculatedAt: now,
      );
    }

    final values = validSamples.map((m) => m.value).toList()..sort();
    final median = _calculateMedian(values);
    final mean = values.reduce((a, b) => a + b) / values.length;
    final stdDev = _calculateStdDev(values, mean);

    final minExpected = max(92.0, median - max(1.5, 1.5 * stdDev));
    final maxExpected = min(100.0, median + max(1.0, 1.5 * stdDev));

    final confidence = min(1.0, 0.75 + (validSamples.length / 10.0) * 0.25);

    return PersonalBaseline(
      type: HealthMetricType.spo2,
      isEstablished: true,
      baselineValue: double.parse(median.toStringAsFixed(1)),
      minExpected: double.parse(minExpected.toStringAsFixed(1)),
      maxExpected: double.parse(maxExpected.toStringAsFixed(1)),
      standardDeviation: double.parse(stdDev.toStringAsFixed(2)),
      sampleCount: validSamples.length,
      confidence: double.parse(confidence.toStringAsFixed(2)),
      statusMessage: 'Resting SpO2 baseline: ${median.toStringAsFixed(0)}% (expected ${minExpected.toStringAsFixed(0)}%–${maxExpected.toStringAsFixed(0)}%)',
      calculatedAt: now,
    );
  }

  // --- Statistical Helpers ---

  double _calculateMedian(List<double> sortedValues) {
    if (sortedValues.isEmpty) return 0.0;
    final mid = sortedValues.length ~/ 2;
    if (sortedValues.length % 2 == 1) {
      return sortedValues[mid];
    }
    return (sortedValues[mid - 1] + sortedValues[mid]) / 2.0;
  }

  double _calculateStdDev(List<double> values, double mean) {
    if (values.length <= 1) return 0.0;
    final sumSquares = values.map((v) => pow(v - mean, 2)).reduce((a, b) => a + b);
    return sqrt(sumSquares / (values.length - 1));
  }
}
