import '../data/models/activity_state.dart';
import '../data/models/health_measurement.dart';
import '../data/models/health_metric_type.dart';

/// The result of an activity context classification.
class ActivityClassificationResult {
  const ActivityClassificationResult({
    required this.state,
    required this.confidence,
    required this.reasons,
    this.estimatedCadenceSpm,
  }) : assert(
         confidence >= 0.0 && confidence <= 1.0,
         'confidence must be between 0.0 and 1.0',
       );

  final ActivityState state;

  /// 0.0 to 1.0 confidence score representing how certain the classifier is
  /// given sensor quality, signal agreement, and data recency.
  final double confidence;

  /// Explainable factors and diagnostic observations that led to this classification.
  final List<String> reasons;

  /// Estimated steps per minute (SPM) if step cadence was computable.
  final double? estimatedCadenceSpm;

  @override
  String toString() =>
      'ActivityClassificationResult(state: ${state.label}, '
      'confidence: ${(confidence * 100).toStringAsFixed(0)}%, '
      'cadence: ${estimatedCadenceSpm?.toStringAsFixed(0) ?? "N/A"} spm, '
      'reasons: $reasons)';
}

/// Real-time Activity Context Classification Engine.
///
/// Classifies the user's physical activity state into [ActivityState]
/// ([resting], [walking], [active], [exercising], [sleeping], or [unknown])
/// using rule-based signal fusion of step cadence, heart rate elevation,
/// and M8 data quality/confidence scores.
///
/// Zero synthetic backfill: If data is missing, stale, or low-quality,
/// returns [ActivityState.unknown] rather than guessing.
class ActivityClassifier {
  const ActivityClassifier();

  /// Classifies the user's current physical activity state.
  ///
  /// [latestHeartRate]: Most recent heart rate measurement (with M8 quality scores).
  /// [recentSteps]: Chronological list of recent step readings (newest first).
  /// [referenceTime]: The reference timestamp (defaults to [DateTime.now]).
  ActivityClassificationResult classify({
    HealthMeasurement? latestHeartRate,
    List<HealthMeasurement> recentSteps = const [],
    DateTime? referenceTime,
  }) {
    final now = referenceTime ?? DateTime.now();
    final reasons = <String>[];

    // 1. Check data presence and freshness
    final isHrAvailable = latestHeartRate != null &&
        latestHeartRate.type == HealthMetricType.heartRate;
    final isHrFresh = isHrAvailable &&
        now.difference(latestHeartRate.timestamp).inSeconds.abs() <= 35;
    final hrQuality = latestHeartRate?.qualityScore ?? 0.0;
    final hrConfidence = latestHeartRate?.confidence ?? 0.0;

    // Filter recent steps within the last 60 seconds
    final validRecentSteps = recentSteps
        .where((m) =>
            m.type == HealthMetricType.steps &&
            now.difference(m.timestamp).inSeconds.abs() <= 60)
        .toList();

    final isStepsFresh = validRecentSteps.isNotEmpty;

    // If neither HR nor steps are fresh and valid, return Unknown
    if (!isHrFresh && !isStepsFresh) {
      reasons.add('no_fresh_sensor_data_available');
      return const ActivityClassificationResult(
        state: ActivityState.unknown,
        confidence: 0.0,
        reasons: ['no_fresh_sensor_data_available'],
      );
    }

    // 2. Compute Step Cadence (Steps Per Minute) if >= 2 step readings in recent history
    double? cadenceSpm;
    double stepConfidence = 0.85;

    if (validRecentSteps.length >= 2) {
      final newestStep = validRecentSteps.first;
      final oldestStep = validRecentSteps.last;
      final deltaSec =
          newestStep.timestamp.difference(oldestStep.timestamp).inMilliseconds /
          1000.0;

      if (deltaSec >= 1.0) {
        final stepDiff = newestStep.value - oldestStep.value;
        if (stepDiff >= 0) {
          final stepsPerSecond = stepDiff / deltaSec;
          cadenceSpm = stepsPerSecond * 60.0;
          reasons.add('cadence_calculated_${cadenceSpm.round()}_spm');
          stepConfidence = (newestStep.confidence ?? 0.9).clamp(0.1, 1.0);
        } else {
          reasons.add('step_counter_reset_detected');
          stepConfidence = 0.40;
        }
      }
    } else if (validRecentSteps.length == 1) {
      reasons.add('single_step_sample_available');
      stepConfidence = (validRecentSteps.first.confidence ?? 0.7) * 0.8;
    }

    // 3. Evaluate Heart Rate Context
    final hrBpm = latestHeartRate?.value ?? 0.0;
    final isHrTrustworthy = isHrFresh && hrQuality >= 0.55 && hrConfidence >= 0.50;

    if (isHrFresh) {
      if (isHrTrustworthy) {
        reasons.add('trusted_hr_${hrBpm.round()}_bpm');
      } else {
        reasons.add('low_quality_hr_degraded_weight');
      }
    } else {
      reasons.add('hr_sensor_absent_or_stale');
    }

    // 4. Decision Matrix: Fusion of Cadence and Heart Rate
    ActivityState classifiedState;
    double confidence;

    if (cadenceSpm != null && cadenceSpm > 0) {
      if (cadenceSpm >= 125.0) {
        // High cadence: Running / Fast Exertion
        classifiedState = ActivityState.exercising;
        reasons.add('high_cadence_exertion');
        confidence = (stepConfidence * 0.95).clamp(0.1, 1.0);
        if (isHrTrustworthy && hrBpm >= 120.0) {
          confidence = (confidence * 1.05).clamp(0.1, 1.0);
          reasons.add('hr_confirms_exercise');
        }
      } else if (cadenceSpm >= 85.0) {
        // Moderate/Brisk Cadence
        classifiedState = ActivityState.active;
        reasons.add('brisk_walking_active_cadence');
        confidence = (stepConfidence * 0.90).clamp(0.1, 1.0);
      } else if (cadenceSpm >= 30.0) {
        // Casual Walking
        classifiedState = ActivityState.walking;
        reasons.add('steady_walking_cadence');
        confidence = (stepConfidence * 0.90).clamp(0.1, 1.0);
      } else {
        // Low/Minimal Cadence (<30 spm: shuffling or fidgeting)
        if (isHrTrustworthy && hrBpm >= 130.0) {
          classifiedState = ActivityState.exercising;
          reasons.add('stationary_high_intensity_exercise');
          confidence = (hrConfidence * 0.85).clamp(0.1, 1.0);
        } else if (isHrTrustworthy && hrBpm >= 100.0) {
          classifiedState = ActivityState.active;
          reasons.add('stationary_elevated_hr_active');
          confidence = (hrConfidence * 0.80).clamp(0.1, 1.0);
        } else {
          classifiedState = ActivityState.resting;
          reasons.add('low_cadence_resting');
          confidence = (stepConfidence * 0.85).clamp(0.1, 1.0);
        }
      }
    } else {
      // No active cadence measured (stationary or step data not yet accumulated)
      if (isHrTrustworthy) {
        if (hrBpm >= 130.0) {
          classifiedState = ActivityState.exercising;
          reasons.add('stationary_high_hr_exercise');
          confidence = (hrConfidence * 0.80).clamp(0.1, 1.0);
        } else if (hrBpm >= 100.0) {
          classifiedState = ActivityState.active;
          reasons.add('stationary_active_elevation');
          confidence = (hrConfidence * 0.75).clamp(0.1, 1.0);
        } else if (hrBpm >= 45.0 && hrBpm < 100.0) {
          classifiedState = ActivityState.resting;
          reasons.add('resting_heart_rate_range');
          confidence = (hrConfidence * 0.90).clamp(0.1, 1.0);
        } else {
          classifiedState = ActivityState.unknown;
          reasons.add('abnormal_unclassified_hr_range');
          confidence = 0.30;
        }
      } else {
        // Step cadence is 0 and HR is untrusted/absent
        classifiedState = ActivityState.unknown;
        reasons.add('insufficient_signal_confidence');
        confidence = 0.20;
      }
    }

    // Explicit check for Sleeping request:
    // Sustained overnight sleep classification requires multi-hour polysomnography/accelerometry
    // which is not supported from momentary spot measurements.
    if (classifiedState == ActivityState.resting && hrBpm < 50.0 && !isStepsFresh) {
      reasons.add('sleep_requires_multi_hour_sleep_staging_unsupported');
    }

    return ActivityClassificationResult(
      state: classifiedState,
      confidence: double.parse(confidence.toStringAsFixed(2)),
      reasons: reasons,
      estimatedCadenceSpm: cadenceSpm != null
          ? double.parse(cadenceSpm.toStringAsFixed(1))
          : null,
    );
  }
}
