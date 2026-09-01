import 'dart:math';

import '../data/models/health_measurement.dart';
import '../data/models/health_metric_type.dart';

/// Assessment result produced by the [DataQualityEngine].
///
/// Contains the calculated [qualityScore], contextual [confidence], and
/// descriptive explainability factors.
class QualityAssessment {
  const QualityAssessment({
    required this.qualityScore,
    required this.confidence,
    required this.factors,
  }) : assert(
         qualityScore >= 0.0 && qualityScore <= 1.0,
         'qualityScore must be between 0.0 and 1.0',
       ),
       assert(
         confidence >= 0.0 && confidence <= 1.0,
         'confidence must be between 0.0 and 1.0',
       );

  /// 0.0 to 1.0 score evaluating the intrinsic quality / signal reliability
  /// of the physical sensor reading (e.g. motion artifact, noise, physiological sanity).
  final double qualityScore;

  /// 0.0 to 1.0 score evaluating overall confidence that the measurement
  /// accurately represents the user's state (combines quality, history depth, and recency).
  final double confidence;

  /// Human-readable tags/reasons explaining the evaluation (e.g. 'stable_signal',
  /// 'rapid_delta_jump', 'sensor_gap', 'physiological_outlier').
  final List<String> factors;

  @override
  String toString() =>
      'QualityAssessment(quality: ${(qualityScore * 100).toStringAsFixed(1)}%, '
      'confidence: ${(confidence * 100).toStringAsFixed(1)}%, factors: $factors)';
}

/// Real-time data quality engine for VitalSync biometrics.
///
/// Evaluates incoming physical sensor readings across distinct per-metric
/// mathematical models (Heart Rate, Steps, SpO2), producing explainable,
/// zero-synthetic-backfill quality and confidence scores.
class DataQualityEngine {
  const DataQualityEngine();

  /// Enriches a [HealthMeasurement] by evaluating its quality and confidence
  /// against its [recentHistory] (chronological, newest-first).
  HealthMeasurement enrich(
    HealthMeasurement measurement,
    List<HealthMeasurement> recentHistory,
  ) {
    final assessment = evaluate(measurement, recentHistory);
    return measurement.copyWith(
      qualityScore: assessment.qualityScore,
      confidence: assessment.confidence,
    );
  }

  /// Evaluates quality and confidence for a given measurement.
  QualityAssessment evaluate(
    HealthMeasurement measurement,
    List<HealthMeasurement> recentHistory,
  ) {
    switch (measurement.type) {
      case HealthMetricType.heartRate:
        return evaluateHeartRate(measurement, recentHistory);
      case HealthMetricType.steps:
        return evaluateSteps(measurement, recentHistory);
      case HealthMetricType.spo2:
        return evaluateSpO2(measurement, recentHistory);
    }
  }

  /// Evaluates continuous Optical PPG Heart Rate measurements.
  ///
  /// Signals analyzed:
  /// - Physiological plausibility bounds (30–220 BPM).
  /// - Rate-of-change / delta jump between consecutive 1Hz samples.
  /// - Rolling standard deviation over a short recent window (motion artifact detection).
  /// - Sampling cadence regularity and inter-packet gap duration.
  /// - History depth / sample stability count.
  QualityAssessment evaluateHeartRate(
    HealthMeasurement current,
    List<HealthMeasurement> history,
  ) {
    final factors = <String>[];
    final bpm = current.value;

    // 1. Base physiological range scoring
    double baseScore;
    if (bpm >= 45 && bpm <= 195) {
      baseScore = 1.0;
      factors.add('optimal_physiological_range');
    } else if ((bpm >= 35 && bpm < 45) || (bpm > 195 && bpm <= 220)) {
      baseScore = 0.70;
      factors.add('extreme_physiological_edge');
    } else if ((bpm >= 25 && bpm < 35) || (bpm > 220 && bpm <= 250)) {
      baseScore = 0.35;
      factors.add('unlikely_physiological_outlier');
    } else {
      baseScore = 0.10;
      factors.add('implausible_optical_noise');
    }

    double deltaPenalty = 0.0;
    double stdDevPenalty = 0.0;
    double cadenceMultiplier = 1.0;

    // Filter relevant recent HR history (within last 30 seconds, excluding current if present)
    final recent = history
        .where((m) =>
            m.type == HealthMetricType.heartRate &&
            m.id != current.id &&
            current.timestamp.difference(m.timestamp).inSeconds.abs() <= 30)
        .toList();

    if (recent.isNotEmpty) {
      final prev = recent.first;
      final timeDeltaSeconds =
          (current.timestamp.difference(prev.timestamp).inMilliseconds.abs()) /
          1000.0;

      // 2. Instantaneous Delta Jump Check
      final bpmDelta = (current.value - prev.value).abs();
      if (timeDeltaSeconds <= 2.0) {
        if (bpmDelta > 40) {
          deltaPenalty = 0.45;
          factors.add('abrupt_bpm_jump_artifact');
        } else if (bpmDelta > 25) {
          deltaPenalty = 0.25;
          factors.add('moderate_bpm_jump');
        } else if (bpmDelta > 15 && timeDeltaSeconds <= 1.0) {
          deltaPenalty = 0.10;
          factors.add('slight_bpm_flutter');
        } else {
          factors.add('stable_delta');
        }
      }

      // 3. Cadence & Gap Check
      if (timeDeltaSeconds <= 2.0) {
        cadenceMultiplier = 1.0;
        factors.add('continuous_cadence');
      } else if (timeDeltaSeconds <= 5.0) {
        cadenceMultiplier = 0.90;
        factors.add('minor_cadence_jitter');
      } else if (timeDeltaSeconds <= 15.0) {
        cadenceMultiplier = 0.75;
        factors.add('cadence_dropout_gap');
      } else {
        cadenceMultiplier = 0.60;
        factors.add('stale_reconnection');
      }

      // 4. Rolling Standard Deviation (Motion / Noise check across >= 3 samples)
      if (recent.length >= 2) {
        final windowValues = [
          current.value,
          ...recent.take(4).map((m) => m.value),
        ];
        final mean =
            windowValues.reduce((a, b) => a + b) / windowValues.length;
        final variance =
            windowValues
                .map((v) => pow(v - mean, 2))
                .reduce((a, b) => a + b) /
            windowValues.length;
        final stdDev = sqrt(variance);

        if (stdDev > 25.0) {
          stdDevPenalty = 0.40;
          factors.add('high_motion_noise');
        } else if (stdDev > 12.0) {
          stdDevPenalty = 0.20;
          factors.add('moderate_motion_variation');
        } else if (stdDev < 6.0) {
          factors.add('low_variance_stable_stream');
        }
      }
    } else {
      factors.add('isolated_first_sample');
    }

    final qualityScore = (
      (baseScore - deltaPenalty - stdDevPenalty).clamp(0.05, 1.0) *
          cadenceMultiplier
    ).clamp(0.05, 1.0);

    // 5. Confidence computation
    // Confidence combines the quality score with sample depth and recency
    double depthFactor;
    if (recent.isEmpty) {
      depthFactor = 0.70;
    } else if (recent.length == 1) {
      depthFactor = 0.85;
    } else {
      depthFactor = 1.0;
    }

    final confidence = (qualityScore * depthFactor).clamp(0.05, 1.0);

    return QualityAssessment(
      qualityScore: double.parse(qualityScore.toStringAsFixed(2)),
      confidence: double.parse(confidence.toStringAsFixed(2)),
      factors: factors,
    );
  }

  /// Evaluates Hardware Cumulative Step Counter measurements.
  ///
  /// Signals analyzed:
  /// - Non-negativity & plausible cumulative range.
  /// - Monotonicity check (detects counter resets or watch reboots).
  /// - Accumulation rate limits (human maximum running cadence ~4.5 steps/sec).
  /// - Time continuity.
  QualityAssessment evaluateSteps(
    HealthMeasurement current,
    List<HealthMeasurement> history,
  ) {
    final factors = <String>[];
    final steps = current.value;

    if (steps < 0 || steps > 200000) {
      return const QualityAssessment(
        qualityScore: 0.05,
        confidence: 0.05,
        factors: ['out_of_bounds_step_count'],
      );
    }

    double qualityScore = 0.98;
    double confidence = 0.95;
    factors.add('valid_step_count');

    final recent = history
        .where((m) =>
            m.type == HealthMetricType.steps &&
            m.id != current.id &&
            current.timestamp.difference(m.timestamp).inHours.abs() <= 24)
        .toList();

    if (recent.isNotEmpty) {
      final prev = recent.first;
      final timeDeltaSeconds =
          (current.timestamp.difference(prev.timestamp).inMilliseconds.abs()) /
          1000.0;

      if (current.value < prev.value) {
        // Step counter reset (reboot or midnight rollover)
        qualityScore = 0.65;
        confidence = 0.50;
        factors.add('counter_reset_or_reboot');
      } else if (timeDeltaSeconds > 0.5) {
        final stepsAdded = current.value - prev.value;
        final stepRatePerSecond = stepsAdded / timeDeltaSeconds;

        // Peak sprinting cadence is ~4.5 steps/sec. Rates > 5.5 steps/sec
        // indicate vehicle vibration or false shaking artifacts.
        if (stepRatePerSecond > 6.0) {
          qualityScore = 0.40;
          confidence = 0.35;
          factors.add('implausible_step_cadence_vibration');
        } else if (stepRatePerSecond > 4.5) {
          qualityScore = 0.75;
          confidence = 0.70;
          factors.add('high_cadence_sprint');
        } else {
          factors.add('normal_cadence_accumulation');
        }
      }
    } else {
      factors.add('initial_step_reading');
      confidence = 0.85;
    }

    return QualityAssessment(
      qualityScore: double.parse(qualityScore.toStringAsFixed(2)),
      confidence: double.parse(confidence.toStringAsFixed(2)),
      factors: factors,
    );
  }

  /// Evaluates On-Demand Blood Oxygen (SpO2) Spot Measurements.
  ///
  /// Signals analyzed:
  /// - Physiological saturation range (95–100% normal, 90–94% mild low, <90% hypoxemic/loose fit).
  /// - Repeat spot-check consistency within short time windows (e.g. 5–10 min).
  /// - Measurement freshness / recency decay.
  QualityAssessment evaluateSpO2(
    HealthMeasurement current,
    List<HealthMeasurement> history,
  ) {
    final factors = <String>[];
    final spo2 = current.value;

    double baseQuality;
    if (spo2 >= 95.0 && spo2 <= 100.0) {
      baseQuality = 1.0;
      factors.add('normal_oxygen_saturation');
    } else if (spo2 >= 90.0 && spo2 < 95.0) {
      baseQuality = 0.85;
      factors.add('mild_low_saturation_or_fit');
    } else if (spo2 >= 80.0 && spo2 < 90.0) {
      baseQuality = 0.60;
      factors.add('hypoxemic_or_sensor_misalignment');
    } else if (spo2 >= 70.0 && spo2 < 80.0) {
      baseQuality = 0.35;
      factors.add('severe_attenuation_light_leak');
    } else {
      baseQuality = 0.05;
      factors.add('invalid_spo2_reading');
    }

    double confidence = baseQuality;

    // Check repeat spot measurements within last 15 minutes
    final recent = history
        .where((m) =>
            m.type == HealthMetricType.spo2 &&
            m.id != current.id &&
            current.timestamp.difference(m.timestamp).inMinutes.abs() <= 15)
        .toList();

    if (recent.isNotEmpty) {
      final prev = recent.first;
      final diff = (current.value - prev.value).abs();

      if (diff <= 2.0) {
        confidence = (confidence * 1.05).clamp(0.05, 1.0);
        factors.add('repeat_spot_check_concordance');
      } else if (diff >= 6.0) {
        confidence = (confidence * 0.75).clamp(0.05, 1.0);
        factors.add('repeat_spot_check_discrepancy');
      }
    } else {
      factors.add('isolated_spot_reading');
    }

    return QualityAssessment(
      qualityScore: double.parse(baseQuality.toStringAsFixed(2)),
      confidence: double.parse(confidence.toStringAsFixed(2)),
      factors: factors,
    );
  }
}
