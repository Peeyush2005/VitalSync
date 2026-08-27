import 'package:flutter_test/flutter_test.dart';
import 'package:vitalsync/data/models/health_data_source.dart';
import 'package:vitalsync/data/models/health_metric_type.dart';
import 'package:vitalsync/data/repositories/fake_health_repository.dart';

void main() {
  late FakeHealthRepository repository;

  setUp(() {
    repository = FakeHealthRepository();
  });

  test('getLatestMeasurement returns a simulated heart rate reading', () async {
    final latest = await repository.getLatestMeasurement(
      HealthMetricType.heartRate,
    );

    expect(latest, isNotNull);
    expect(latest!.type, HealthMetricType.heartRate);
    expect(latest.source, HealthDataSource.simulated);
    expect(latest.value, greaterThan(0));
  });

  test('getMeasurementHistory returns newest-first, bounded by limit', () async {
    final history = await repository.getMeasurementHistory(
      HealthMetricType.heartRate,
      limit: 5,
    );

    expect(history.length, 5);
    for (var i = 0; i < history.length - 1; i++) {
      expect(
        history[i].timestamp.isAfter(history[i + 1].timestamp) ||
            history[i].timestamp.isAtSameMomentAs(history[i + 1].timestamp),
        isTrue,
      );
    }
  });

  test('heart rate values stay within a plausible physiological range', () async {
    final history = await repository.getMeasurementHistory(
      HealthMetricType.heartRate,
      limit: 48,
    );

    for (final measurement in history) {
      expect(measurement.value, inInclusiveRange(45, 190));
    }
  });

  test('repeated reads are stable within the same instance', () async {
    final first = await repository.getLatestMeasurement(
      HealthMetricType.heartRate,
    );
    final second = await repository.getLatestMeasurement(
      HealthMetricType.heartRate,
    );

    expect(first, equals(second));
  });

  test('steps history has plausible non-negative values', () async {
    final history = await repository.getMeasurementHistory(
      HealthMetricType.steps,
    );

    expect(history, isNotEmpty);
    for (final measurement in history) {
      expect(measurement.value, greaterThanOrEqualTo(0));
    }
  });
}
