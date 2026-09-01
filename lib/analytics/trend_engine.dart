import 'dart:math';

import '../data/models/activity_state.dart';
import '../data/models/health_measurement.dart';
import '../data/models/health_metric_type.dart';
import 'personal_baseline_engine.dart';

/// Detected direction and character of a metric trend.
enum TrendDirection {
  stable,
  increasing,
  decreasing,
  suddenShift,
  repeatedDeviation,
  insufficientData;

  String get label {
    switch (this) {
      case TrendDirection.stable:
        return 'Stable';
      case TrendDirection.increasing:
        return 'Elevated Trend';
      case TrendDirection.decreasing:
        return 'Decreasing Trend';
      case TrendDirection.suddenShift:
        return 'Acute Shift';
      case TrendDirection.repeatedDeviation:
        return 'Repeated Deviation';
      case TrendDirection.insufficientData:
        return 'Collecting Data';
    }
  }
}

/// A timestamped point in a metric's trend time series (e.g. daily resting HR median,
/// daily step total, or individual SpO2 spot check).
class TrendDataPoint {
  const TrendDataPoint({
    required this.timestamp,
    required this.value,
    this.qualityScore = 1.0,
    this.sampleCount = 1,
  });

  final DateTime timestamp;
  final double value;
  final double qualityScore;
  final int sampleCount;
}

/// Result of a trend analysis.
///
/// Designed to be consumed by M11 UI and future M12 Anomaly Detection / M14 Insights.
class MetricTrend {
  const MetricTrend({
    required this.type,
    required this.direction,
    required this.confidence,
    required this.headline,
    required this.message,
    required this.factors,
    required this.calculatedAt,
    this.recentAverage,
    this.rollingStandardDeviation,
    this.percentChange,
    this.zScore,
    this.slope,
    this.windowDays,
    this.sampleCount = 0,
    this.dataQualityScore,
  }) : assert(
         confidence >= 0.0 && confidence <= 1.0,
         'confidence must be between 0.0 and 1.0',
       );

  final HealthMetricType type;
  final TrendDirection direction;

  /// 0.0 to 1.0 confidence score based on sample depth, time-span, and M8 signal quality.
  final double confidence;

  /// Summary headline (e.g. "Resting heart rate is stable", "Resting heart rate slightly elevated").
  final String headline;

  /// Plain-language, non-diagnostic explanation of the trend.
  final String message;

  /// Explainable diagnostic factors behind the detection.
  final List<String> factors;

  /// Moving average of recent aggregated points evaluated.
  final double? recentAverage;

  /// Rolling standard deviation across recent points to characterize normal variability.
  final double? rollingStandardDeviation;

  /// Percentage change relative to personal baseline.
  final double? percentChange;

  /// Statistical Z-Score relative to personal baseline standard deviation.
  final double? zScore;

  /// Linear regression slope (units per day) over the trend window.
  final double? slope;

  /// Number of days spanned by the trend evaluation window.
  final int? windowDays;

  /// Number of aggregated points / raw valid samples used in this trend analysis.
  final int sampleCount;

  /// Mean M8 data quality score across the evaluated points.
  final double? dataQualityScore;

  final DateTime calculatedAt;

  @override
  String toString() =>
      'MetricTrend(type: ${type.name}, direction: ${direction.label}, '
      'zScore: ${zScore?.toStringAsFixed(2) ?? "N/A"}, '
      'percentChange: ${percentChange != null ? "${percentChange! > 0 ? "+" : ""}${percentChange!.toStringAsFixed(1)}%" : "N/A"}, '
      'rollingStdDev: ${rollingStandardDeviation?.toStringAsFixed(2) ?? "N/A"}, '
      'confidence: ${(confidence * 100).toStringAsFixed(0)}%)';
}

/// Simple Statistics Trend Engine for VitalSync biometrics.
///
/// Uses rolling averages, rolling standard deviation, Z-scores, and slope across
/// historical measurements and M10 personal baselines:
/// - Evaluates trend patterns without opaque ML models.
/// - Gated on M8 data quality (excludes low quality readings and discounts confidence
///   when the excluded fraction is high).
/// - Gated on sufficient history (both sample count and time span per metric).
/// - Per-metric windowing tailored to physiological sampling patterns:
///     * HR: 7-day window, daily resting medians.
///     * Steps: 7-day window, daily cumulative totals.
///     * SpO2: 14-day window, individual sparse spot checks.
/// - Produces explainable, non-diagnostic product insights.
class TrendEngine {
  const TrendEngine();

  // Minimum quality threshold to include a sample in trend calculation (matches M10)
  static const double minQualityThreshold = 0.60;

  // Minimum required aggregated data points to evaluate trend
  static const int minHrDays = 3;
  static const int minStepsDays = 3;
  static const int minSpo2Points = 3;

  // Window lookback durations
  static const Duration hrWindow = Duration(days: 7);
  static const Duration stepsWindow = Duration(days: 7);
  static const Duration spo2Window = Duration(days: 14);

  /// Evaluates trend for [type] given recent [history] and [baseline].
  MetricTrend analyzeTrend({
    required HealthMetricType type,
    required List<HealthMeasurement> history,
    required PersonalBaseline baseline,
    DateTime? referenceTime,
  }) {
    final now = referenceTime ?? DateTime.now();

    switch (type) {
      case HealthMetricType.heartRate:
        return _analyzeHeartRateTrend(history, baseline, now);
      case HealthMetricType.steps:
        return _analyzeStepsTrend(history, baseline, now);
      case HealthMetricType.spo2:
        return _analyzeSpo2Trend(history, baseline, now);
    }
  }

  // --- Heart Rate Trend Analysis ---
  // Window: 7 days. Aggregation: daily median of Resting measurements.

  MetricTrend _analyzeHeartRateTrend(
    List<HealthMeasurement> history,
    PersonalBaseline baseline,
    DateTime now,
  ) {
    const type = HealthMetricType.heartRate;
    final factors = <String>[];

    // Filter to HR in window
    final windowStart = now.subtract(hrWindow);
    final rawInWindow = history.where((m) =>
        m.type == type &&
        m.timestamp.isAfter(windowStart) &&
        !m.timestamp.isAfter(now)).toList();

    // Separate resting vs active, and evaluate quality
    final restingSamples = rawInWindow.where((m) {
      if (m.activityState != null) {
        return m.activityState == ActivityState.resting;
      }
      return m.value <= 90.0;
    }).toList();

    final validResting = restingSamples
        .where((m) => (m.qualityScore ?? 1.0) >= minQualityThreshold)
        .toList();

    // Data quality gating: ratio of valid to total resting samples
    final double qualityRatio = restingSamples.isEmpty
        ? 1.0
        : validResting.length / restingSamples.length;

    // Aggregate into daily resting medians
    final dailyPoints = _aggregateDailyRestingHeartRate(validResting);

    // History & baseline gating
    if (!baseline.isEstablished || dailyPoints.length < minHrDays) {
      return _insufficientDataTrend(
        type: type,
        now: now,
        baseline: baseline,
        actualCount: dailyPoints.length,
        requiredCount: minHrDays,
        itemLabel: 'days of resting heart rate data',
      );
    }

    return _computeStatisticalTrend(
      type: type,
      points: dailyPoints,
      baseline: baseline,
      qualityRatio: qualityRatio,
      windowDays: 7,
      now: now,
      factors: factors,
      zScoreElevationThreshold: 1.25,
      percentChangeThreshold: 8.0,
      acuteShiftZScore: 2.2,
    );
  }

  List<TrendDataPoint> _aggregateDailyRestingHeartRate(
    List<HealthMeasurement> measurements,
  ) {
    // Group by calendar day (yyyy-MM-dd)
    final Map<String, List<HealthMeasurement>> byDay = {};
    for (final m in measurements) {
      final key = '${m.timestamp.year}-${m.timestamp.month.toString().padLeft(2, '0')}-${m.timestamp.day.toString().padLeft(2, '0')}';
      byDay.putIfAbsent(key, () => []).add(m);
    }

    final points = <TrendDataPoint>[];
    for (final entry in byDay.entries) {
      final daySamples = entry.value;
      final sortedValues = daySamples.map((m) => m.value).toList()..sort();
      final median = _calculateMedian(sortedValues);
      final avgQuality = daySamples
          .map((m) => m.qualityScore ?? 1.0)
          .reduce((a, b) => a + b) / daySamples.length;

      // Representative timestamp is the noon of that day or the middle sample
      final midTimestamp = daySamples[daySamples.length ~/ 2].timestamp;

      points.add(
        TrendDataPoint(
          timestamp: midTimestamp,
          value: median,
          qualityScore: avgQuality,
          sampleCount: daySamples.length,
        ),
      );
    }

    // Sort chronologically ascending
    points.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return points;
  }

  // --- Steps Trend Analysis ---
  // Window: 7 days. Aggregation: daily totals derived from cumulative/hourly measurements.

  MetricTrend _analyzeStepsTrend(
    List<HealthMeasurement> history,
    PersonalBaseline baseline,
    DateTime now,
  ) {
    const type = HealthMetricType.steps;
    final factors = <String>[];

    final windowStart = now.subtract(stepsWindow);
    final rawInWindow = history.where((m) =>
        m.type == type &&
        m.timestamp.isAfter(windowStart) &&
        !m.timestamp.isAfter(now)).toList();

    final validSamples = rawInWindow
        .where((m) => (m.qualityScore ?? 1.0) >= minQualityThreshold && m.value >= 0)
        .toList();

    final double qualityRatio = rawInWindow.isEmpty
        ? 1.0
        : validSamples.length / rawInWindow.length;

    // Aggregate into daily step totals
    final dailyPoints = _aggregateDailySteps(validSamples);

    if (!baseline.isEstablished || dailyPoints.length < minStepsDays) {
      return _insufficientDataTrend(
        type: type,
        now: now,
        baseline: baseline,
        actualCount: dailyPoints.length,
        requiredCount: minStepsDays,
        itemLabel: 'days of step activity',
      );
    }

    return _computeStatisticalTrend(
      type: type,
      points: dailyPoints,
      baseline: baseline,
      qualityRatio: qualityRatio,
      windowDays: 7,
      now: now,
      factors: factors,
      zScoreElevationThreshold: 1.2,
      percentChangeThreshold: 15.0,
      acuteShiftZScore: 2.3,
    );
  }

  List<TrendDataPoint> _aggregateDailySteps(
    List<HealthMeasurement> measurements,
  ) {
    final Map<String, List<HealthMeasurement>> byDay = {};
    for (final m in measurements) {
      final key = '${m.timestamp.year}-${m.timestamp.month.toString().padLeft(2, '0')}-${m.timestamp.day.toString().padLeft(2, '0')}';
      byDay.putIfAbsent(key, () => []).add(m);
    }

    final points = <TrendDataPoint>[];
    for (final entry in byDay.entries) {
      final daySamples = entry.value;
      // Sort chronologically ascending
      daySamples.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      // Steps can be recorded either as:
      // 1) Cumulative counter (e.g. 100, 350, 1200, 5000) -> daily total is max - min (or max if starting near 0)
      // 2) Bucket/hourly totals (e.g. 300, 450, 600) -> daily total is sum
      double dailyTotal;
      final isMonotonic = _isRoughlyMonotonic(daySamples.map((s) => s.value).toList());

      if (isMonotonic && daySamples.length > 1 && daySamples.last.value > daySamples.first.value * 1.5) {
        // Cumulative counter: max value of the day represents total accumulated steps
        dailyTotal = daySamples.map((m) => m.value).reduce(max);
      } else {
        // Sum of recorded periodic intervals or max if single reading
        if (daySamples.length == 1) {
          dailyTotal = daySamples.first.value;
        } else {
          // If values look like periodic buckets, sum them
          dailyTotal = daySamples.map((m) => m.value).reduce((a, b) => a + b);
        }
      }

      final avgQuality = daySamples
          .map((m) => m.qualityScore ?? 1.0)
          .reduce((a, b) => a + b) / daySamples.length;

      points.add(
        TrendDataPoint(
          timestamp: daySamples.last.timestamp,
          value: dailyTotal,
          qualityScore: avgQuality,
          sampleCount: daySamples.length,
        ),
      );
    }

    points.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return points;
  }

  bool _isRoughlyMonotonic(List<double> values) {
    if (values.length < 2) return true;
    int decreases = 0;
    for (var i = 1; i < values.length; i++) {
      if (values[i] < values[i - 1]) decreases++;
    }
    return decreases <= 1; // Allow at most 1 reset
  }

  // --- SpO2 Trend Analysis ---
  // Window: 14 days (sparse on-demand readings). No daily median aggregation required —
  // evaluate individual spot checks directly with chronological weighting.

  MetricTrend _analyzeSpo2Trend(
    List<HealthMeasurement> history,
    PersonalBaseline baseline,
    DateTime now,
  ) {
    const type = HealthMetricType.spo2;
    final factors = <String>[];

    final windowStart = now.subtract(spo2Window);
    final rawInWindow = history.where((m) =>
        m.type == type &&
        m.timestamp.isAfter(windowStart) &&
        !m.timestamp.isAfter(now)).toList();

    final validSamples = rawInWindow
        .where((m) =>
            (m.qualityScore ?? 1.0) >= minQualityThreshold &&
            m.value >= 80.0 &&
            m.value <= 100.0)
        .toList();

    final double qualityRatio = rawInWindow.isEmpty
        ? 1.0
        : validSamples.length / rawInWindow.length;

    // Convert directly to TrendDataPoints (chronological)
    final points = validSamples.map((m) {
      return TrendDataPoint(
        timestamp: m.timestamp,
        value: m.value,
        qualityScore: m.qualityScore ?? 1.0,
      );
    }).toList()..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    if (!baseline.isEstablished || points.length < minSpo2Points) {
      return _insufficientDataTrend(
        type: type,
        now: now,
        baseline: baseline,
        actualCount: points.length,
        requiredCount: minSpo2Points,
        itemLabel: 'SpO2 spot measurements',
      );
    }

    return _computeStatisticalTrend(
      type: type,
      points: points,
      baseline: baseline,
      qualityRatio: qualityRatio,
      windowDays: 14,
      now: now,
      factors: factors,
      zScoreElevationThreshold: 1.3,
      percentChangeThreshold: 3.0, // SpO2 changes are physiologically small
      acuteShiftZScore: 2.1,
    );
  }

  // --- Core Statistical Computation & Classification ---

  MetricTrend _computeStatisticalTrend({
    required HealthMetricType type,
    required List<TrendDataPoint> points,
    required PersonalBaseline baseline,
    required double qualityRatio,
    required int windowDays,
    required DateTime now,
    required List<String> factors,
    required double zScoreElevationThreshold,
    required double percentChangeThreshold,
    required double acuteShiftZScore,
  }) {
    final values = points.map((p) => p.value).toList();
    final n = values.length;

    // 1. Moving Average / Recent Mean
    final recentMean = values.reduce((a, b) => a + b) / n;

    // 2. Rolling Standard Deviation across the points
    final rollingStdDev = _calculateStdDev(values, recentMean);

    // 3. Baseline comparison & Z-Score
    final baselineVal = baseline.baselineValue!;
    // Use baseline stddev if available and non-trivial; else fallback to robust minimum
    final baselineStdDev = max(
      1.0,
      baseline.standardDeviation ?? (type == HealthMetricType.steps ? 1500.0 : 3.0),
    );

    final zScore = (recentMean - baselineVal) / baselineStdDev;
    final percentChange = ((recentMean - baselineVal) / baselineVal) * 100.0;

    // 4. Slope Calculation (units per day)
    final slope = _calculateSlopePerDay(points);

    // 5. Data Quality Factor
    final avgQuality = points.map((p) => p.qualityScore).reduce((a, b) => a + b) / n;
    final combinedQuality = avgQuality * qualityRatio;

    factors.add('points_count_$n');
    factors.add('recent_mean_${recentMean.toStringAsFixed(1)}');
    factors.add('baseline_${baselineVal.toStringAsFixed(1)}');
    factors.add('z_score_${zScore.toStringAsFixed(2)}');
    factors.add('rolling_stddev_${rollingStdDev.toStringAsFixed(2)}');
    factors.add('slope_per_day_${slope.toStringAsFixed(2)}');
    factors.add('data_quality_${(combinedQuality * 100).toStringAsFixed(0)}%');

    // 6. Check for Repeated Deviations (points fluctuating outside expected range back & forth)
    final minExpected = baseline.minExpected ?? (baselineVal - 1.5 * baselineStdDev);
    final maxExpected = baseline.maxExpected ?? (baselineVal + 1.5 * baselineStdDev);

    int outsideCount = 0;
    int directionChanges = 0;
    int? lastDeviationSign; // +1 if above, -1 if below, 0 if within

    for (final p in points) {
      if (p.value > maxExpected) {
        outsideCount++;
        if (lastDeviationSign != null && lastDeviationSign != 1 && lastDeviationSign != 0) {
          directionChanges++;
        }
        lastDeviationSign = 1;
      } else if (p.value < minExpected) {
        outsideCount++;
        if (lastDeviationSign != null && lastDeviationSign != -1 && lastDeviationSign != 0) {
          directionChanges++;
        }
        lastDeviationSign = -1;
      } else {
        lastDeviationSign = 0;
      }
    }

    final hasRepeatedDeviations = outsideCount >= 2 &&
        (directionChanges >= 1 || (outsideCount >= 3 && zScore.abs() < 1.0));

    // 7. Trend Direction Classification
    TrendDirection direction;
    String headline;
    String message;
    final unit = type.defaultUnit;

    if (zScore.abs() >= acuteShiftZScore) {
      direction = TrendDirection.suddenShift;
      final isHigher = zScore > 0;
      headline = isHigher
          ? 'Acute elevation detected'
          : 'Notable drop detected';
      message =
          'Recent readings average ${recentMean.round()} $unit (${percentChange.abs().toStringAsFixed(0)}% ${isHigher ? "above" : "below"} your typical baseline). Worth monitoring if sustained.';
      factors.add('acute_z_score_shift');
    } else if (hasRepeatedDeviations) {
      direction = TrendDirection.repeatedDeviation;
      headline = 'Fluctuating readings detected';
      message =
          'Your ${type.label.toLowerCase()} has shown recurring fluctuations outside your expected range (${minExpected.round()}–${maxExpected.round()} $unit) over the past $windowDays days.';
      factors.add('repeated_range_deviations');
    } else if (zScore >= zScoreElevationThreshold || (percentChange >= percentChangeThreshold && slope > 0.05)) {
      direction = TrendDirection.increasing;
      headline = '${type.label} trending higher';
      message =
          'Your recent average of ${recentMean.round()} $unit is running slightly above your typical baseline of ${baselineVal.round()} $unit over the past $windowDays days.';
      factors.add('statistically_elevated_trend');
    } else if (zScore <= -zScoreElevationThreshold || (percentChange <= -percentChangeThreshold && slope < -0.05)) {
      direction = TrendDirection.decreasing;
      headline = '${type.label} trending lower';
      message =
          'Your recent average of ${recentMean.round()} $unit is running below your typical baseline of ${baselineVal.round()} $unit over the past $windowDays days.';
      factors.add('statistically_lowered_trend');
    } else {
      direction = TrendDirection.stable;
      headline = '${type.label} is stable';
      message =
          'Your recent readings (${recentMean.round()} $unit) remain well within your expected baseline range (${minExpected.round()}–${maxExpected.round()} $unit).';
      factors.add('within_expected_baseline_range');
    }

    // 8. Confidence Gating
    // Factors: baseline confidence, combined quality ratio, sample depth
    final sampleDepthFactor = min(1.0, n / (windowDays == 14 ? 6.0 : 5.0));
    final confidence = (baseline.confidence * combinedQuality * (0.6 + 0.4 * sampleDepthFactor)).clamp(0.1, 1.0);

    return MetricTrend(
      type: type,
      direction: direction,
      recentAverage: double.parse(recentMean.toStringAsFixed(1)),
      rollingStandardDeviation: double.parse(rollingStdDev.toStringAsFixed(2)),
      percentChange: double.parse(percentChange.toStringAsFixed(1)),
      zScore: double.parse(zScore.toStringAsFixed(2)),
      slope: double.parse(slope.toStringAsFixed(3)),
      windowDays: windowDays,
      sampleCount: n,
      dataQualityScore: double.parse(combinedQuality.toStringAsFixed(2)),
      confidence: double.parse(confidence.toStringAsFixed(2)),
      headline: headline,
      message: message,
      factors: factors,
      calculatedAt: now,
    );
  }

  MetricTrend _insufficientDataTrend({
    required HealthMetricType type,
    required DateTime now,
    required PersonalBaseline baseline,
    required int actualCount,
    required int requiredCount,
    required String itemLabel,
  }) {
    final needed = max(1, requiredCount - actualCount);
    final statusMsg = !baseline.isEstablished
        ? 'Your personal baseline is still being established.'
        : 'Need $needed more $itemLabel to evaluate trend patterns.';

    return MetricTrend(
      type: type,
      direction: TrendDirection.insufficientData,
      confidence: 0.0,
      headline: 'Collecting trend history',
      message: statusMsg,
      factors: [
        if (!baseline.isEstablished) 'unestablished_baseline',
        'insufficient_trend_points_${actualCount}_of_$requiredCount',
      ],
      windowDays: type == HealthMetricType.spo2 ? 14 : 7,
      sampleCount: actualCount,
      calculatedAt: now,
    );
  }

  // --- Math Helpers ---

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

  /// Calculates the linear regression slope in units per day.
  double _calculateSlopePerDay(List<TrendDataPoint> points) {
    if (points.length < 2) return 0.0;
    final firstTime = points.first.timestamp.millisecondsSinceEpoch;
    final msPerDay = 86400000.0;

    final xValues = points
        .map((p) => (p.timestamp.millisecondsSinceEpoch - firstTime) / msPerDay)
        .toList();
    final yValues = points.map((p) => p.value).toList();
    final n = points.length;

    final xMean = xValues.reduce((a, b) => a + b) / n;
    final yMean = yValues.reduce((a, b) => a + b) / n;

    double numerator = 0.0;
    double denominator = 0.0;

    for (var i = 0; i < n; i++) {
      final xDiff = xValues[i] - xMean;
      final yDiff = yValues[i] - yMean;
      numerator += xDiff * yDiff;
      denominator += xDiff * xDiff;
    }

    return denominator == 0 ? 0.0 : numerator / denominator;
  }
}
