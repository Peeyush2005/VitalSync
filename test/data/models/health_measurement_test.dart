import 'package:flutter_test/flutter_test.dart';
import 'package:vitalsync/data/models/health_data_source.dart';
import 'package:vitalsync/data/models/health_measurement.dart';
import 'package:vitalsync/data/models/health_metric_type.dart';

void main() {
  HealthMeasurement makeMeasurement({double value = 70}) {
    return HealthMeasurement(
      id: '1',
      userId: 'user-1',
      type: HealthMetricType.heartRate,
      value: value,
      unit: 'bpm',
      timestamp: DateTime(2026, 1, 1, 12),
      source: HealthDataSource.simulated,
      qualityScore: 0.9,
      confidence: 0.8,
    );
  }

  test('equal measurements compare equal', () {
    expect(makeMeasurement(), equals(makeMeasurement()));
  });

  test('copyWith overrides only the given fields', () {
    final original = makeMeasurement();
    final updated = original.copyWith(value: 99);

    expect(updated.value, 99);
    expect(updated.id, original.id);
    expect(updated.type, original.type);
  });

  test('rejects an out-of-range qualityScore', () {
    expect(
      () => HealthMeasurement(
        id: '1',
        userId: 'user-1',
        type: HealthMetricType.heartRate,
        value: 70,
        unit: 'bpm',
        timestamp: DateTime(2026, 1, 1),
        source: HealthDataSource.simulated,
        qualityScore: 1.5,
      ),
      throwsA(isA<AssertionError>()),
    );
  });

  test('toString does not leak the raw measurement value', () {
    final measurement = makeMeasurement(value: 123.4);
    expect(measurement.toString(), isNot(contains('123.4')));
  });
}
