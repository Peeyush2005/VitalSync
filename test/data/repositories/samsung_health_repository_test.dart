import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalsync/data/models/health_data_source.dart';
import 'package:vitalsync/data/models/health_measurement.dart';
import 'package:vitalsync/data/models/health_metric_type.dart';
import 'package:vitalsync/data/repositories/samsung_health_repository.dart';

void main() {
  group('SamsungHealthRepository', () {
    test('returns null and empty list when no data has been received', () async {
      final repo = SamsungHealthRepository();

      final latestHr = await repo.getLatestMeasurement(HealthMetricType.heartRate);
      final history = await repo.getMeasurementHistory(HealthMetricType.heartRate);

      expect(latestHr, isNull);
      expect(history, isEmpty);
    });

    test('stores and returns measurements from real-time stream', () async {
      final controller = StreamController<HealthMeasurement>();
      final repo = SamsungHealthRepository(dataStream: controller.stream);

      final m1 = HealthMeasurement(
        id: 'm1',
        userId: 'u1',
        type: HealthMetricType.heartRate,
        value: 72,
        unit: 'bpm',
        timestamp: DateTime(2026, 8, 28, 10, 0, 0),
        source: HealthDataSource.galaxyWatch,
      );

      final m2 = HealthMeasurement(
        id: 'm2',
        userId: 'u1',
        type: HealthMetricType.heartRate,
        value: 78,
        unit: 'bpm',
        timestamp: DateTime(2026, 8, 28, 10, 0, 10),
        source: HealthDataSource.galaxyWatch,
      );

      controller.add(m1);
      controller.add(m2);

      // Wait a microtask for stream processing
      await Future<void>.delayed(Duration.zero);

      final latest = await repo.getLatestMeasurement(HealthMetricType.heartRate);
      final history = await repo.getMeasurementHistory(HealthMetricType.heartRate);

      expect(latest?.value, 78.0);
      expect(history.length, 2);
      expect(history.first.value, 78.0);
      expect(history.last.value, 72.0);

      repo.dispose();
      await controller.close();
    });

    test('stores and returns step measurements independently from heart rate', () async {
      final controller = StreamController<HealthMeasurement>();
      final repo = SamsungHealthRepository(dataStream: controller.stream);

      final hr = HealthMeasurement(
        id: 'hr_1',
        userId: 'u1',
        type: HealthMetricType.heartRate,
        value: 75,
        unit: 'bpm',
        timestamp: DateTime(2026, 8, 28, 10, 0, 0),
        source: HealthDataSource.galaxyWatch,
      );

      final step = HealthMeasurement(
        id: 'step_1',
        userId: 'u1',
        type: HealthMetricType.steps,
        value: 1250,
        unit: 'steps',
        timestamp: DateTime(2026, 8, 28, 10, 0, 5),
        source: HealthDataSource.galaxyWatch,
      );

      controller.add(hr);
      controller.add(step);

      await Future<void>.delayed(Duration.zero);

      final latestHr = await repo.getLatestMeasurement(HealthMetricType.heartRate);
      final latestSteps = await repo.getLatestMeasurement(HealthMetricType.steps);

      expect(latestHr?.value, 75.0);
      expect(latestHr?.unit, 'bpm');
      expect(latestSteps?.value, 1250.0);
      expect(latestSteps?.unit, 'steps');

      repo.dispose();
      await controller.close();
    });

    test('stores and returns SpO2 spot measurements independently', () async {
      final controller = StreamController<HealthMeasurement>();
      final repo = SamsungHealthRepository(dataStream: controller.stream);

      final spo2 = HealthMeasurement(
        id: 'spo2_1',
        userId: 'u1',
        type: HealthMetricType.spo2,
        value: 99,
        unit: '%',
        timestamp: DateTime(2026, 8, 28, 10, 0, 10),
        source: HealthDataSource.galaxyWatch,
      );

      controller.add(spo2);
      await Future<void>.delayed(Duration.zero);

      final latestSpO2 = await repo.getLatestMeasurement(HealthMetricType.spo2);
      expect(latestSpO2?.value, 99.0);
      expect(latestSpO2?.unit, '%');

      repo.dispose();
      await controller.close();
    });

    test('history honors limit and maxHistorySize bounding', () async {
      final repo = SamsungHealthRepository(maxHistorySize: 5);

      for (var i = 1; i <= 10; i++) {
        repo.recordMeasurement(
          HealthMeasurement(
            id: 'm_$i',
            userId: 'u1',
            type: HealthMetricType.heartRate,
            value: 60.0 + i,
            unit: 'bpm',
            timestamp: DateTime(2026, 8, 28, 10, 0, i),
            source: HealthDataSource.galaxyWatch,
          ),
        );
      }

      final fullHistory = await repo.getMeasurementHistory(HealthMetricType.heartRate);
      expect(fullHistory.length, 5); // Capped at maxHistorySize = 5
      expect(fullHistory.first.value, 70.0); // m_10

      final limitedHistory = await repo.getMeasurementHistory(
        HealthMetricType.heartRate,
        limit: 3,
      );
      expect(limitedHistory.length, 3);
      expect(limitedHistory.map((m) => m.value), [70.0, 69.0, 68.0]);
    });
  });
}
