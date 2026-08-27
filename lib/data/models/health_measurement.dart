import 'activity_state.dart';
import 'health_data_source.dart';
import 'health_metric_type.dart';

/// A single reusable health measurement record.
///
/// This is the shared shape for every kind of reading collected by
/// VitalSync, regardless of its source (Galaxy Watch, Samsung Health,
/// manual entry, or simulated demo data). Analytics (quality, confidence,
/// baselines, trends) all operate on this type.
class HealthMeasurement {
  const HealthMeasurement({
    required this.id,
    required this.userId,
    required this.type,
    required this.value,
    required this.unit,
    required this.timestamp,
    required this.source,
    this.activityState,
    this.qualityScore,
    this.confidence,
  }) : assert(
         qualityScore == null || (qualityScore >= 0 && qualityScore <= 1),
         'qualityScore must be between 0 and 1',
       ),
       assert(
         confidence == null || (confidence >= 0 && confidence <= 1),
         'confidence must be between 0 and 1',
       );

  final String id;
  final String userId;
  final HealthMetricType type;
  final double value;
  final String unit;
  final DateTime timestamp;
  final HealthDataSource source;
  final ActivityState? activityState;

  /// 0.0-1.0 assessment of how reliable this reading is (e.g. sensor
  /// contact, motion artifacts). Set by the data-quality engine.
  final double? qualityScore;

  /// 0.0-1.0 confidence that this reading reflects the user's true state.
  /// Distinct from [qualityScore]: quality is about the measurement
  /// itself, confidence factors in context (e.g. history available).
  final double? confidence;

  HealthMeasurement copyWith({
    String? id,
    String? userId,
    HealthMetricType? type,
    double? value,
    String? unit,
    DateTime? timestamp,
    HealthDataSource? source,
    ActivityState? activityState,
    double? qualityScore,
    double? confidence,
  }) {
    return HealthMeasurement(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      type: type ?? this.type,
      value: value ?? this.value,
      unit: unit ?? this.unit,
      timestamp: timestamp ?? this.timestamp,
      source: source ?? this.source,
      activityState: activityState ?? this.activityState,
      qualityScore: qualityScore ?? this.qualityScore,
      confidence: confidence ?? this.confidence,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is HealthMeasurement &&
        other.id == id &&
        other.userId == userId &&
        other.type == type &&
        other.value == value &&
        other.unit == unit &&
        other.timestamp == timestamp &&
        other.source == source &&
        other.activityState == activityState &&
        other.qualityScore == qualityScore &&
        other.confidence == confidence;
  }

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    type,
    value,
    unit,
    timestamp,
    source,
    activityState,
    qualityScore,
    confidence,
  );

  @override
  String toString() =>
      'HealthMeasurement(id: $id, type: $type, source: $source, '
      'timestamp: $timestamp)';
}
