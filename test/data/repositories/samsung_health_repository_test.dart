import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vitalsync/data/local/health_database.dart';
import 'package:vitalsync/data/models/health_data_source.dart';
import 'package:vitalsync/data/models/health_measurement.dart';
import 'package:vitalsync/data/models/health_metric_type.dart';
import 'package:vitalsync/data/repositories/samsung_health_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('SamsungHealthRepository', () {
    test('returns null and empty list when no data has been received', () async {
      final db = HealthDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      final repo = SamsungHealthRepository(database: db);

      final latestHr = await repo.getLatestMeasurement(HealthMetricType.heartRate);
      final history = await repo.getMeasurementHistory(HealthMetricType.heartRate);

      expect(latestHr, isNull);
      expect(history, isEmpty);
      repo.dispose();
      await db.close();
    });

    test('stores and returns measurements from real-time stream', () async {
      final db = HealthDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      final controller = StreamController<HealthMeasurement>();
      final repo = SamsungHealthRepository(
        dataStream: controller.stream,
        database: db,
      );

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
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final latest = await repo.getLatestMeasurement(HealthMetricType.heartRate);
      final history = await repo.getMeasurementHistory(HealthMetricType.heartRate);

      expect(latest?.value, 78.0);
      expect(latest?.qualityScore, isNotNull);
      expect(latest?.confidence, isNotNull);
      expect(history.length, 2);
      expect(history.first.value, 78.0);
      expect(history.last.value, 72.0);

      repo.dispose();
      await controller.close();
      await db.close();
    });

    test('persists measurements to database and restores on restart', () async {
      final db = HealthDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );

      final repo1 = SamsungHealthRepository(database: db);
      repo1.recordMeasurement(
        HealthMeasurement(
          id: 'hr_persist',
          userId: 'u1',
          type: HealthMetricType.heartRate,
          value: 74.0,
          unit: 'bpm',
          timestamp: DateTime(2026, 8, 28, 10, 0, 0),
          source: HealthDataSource.galaxyWatch,
        ),
      );

      // Wait for async persistence
      await Future<void>.delayed(const Duration(milliseconds: 50));
      repo1.dispose();

      // Start new repository instance using same database (simulating app restart)
      final repo2 = SamsungHealthRepository(database: db);
      final restored = await repo2.getLatestMeasurement(HealthMetricType.heartRate);
      expect(restored, isNotNull);
      expect(restored?.value, equals(74.0));
      expect(restored?.id, equals('hr_persist'));

      repo2.dispose();
      await db.close();
    });

    test('stores and returns step measurements independently from heart rate', () async {
      final db = HealthDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      final controller = StreamController<HealthMeasurement>();
      final repo = SamsungHealthRepository(
        dataStream: controller.stream,
        database: db,
      );

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

      await Future<void>.delayed(const Duration(milliseconds: 50));

      final latestHr = await repo.getLatestMeasurement(HealthMetricType.heartRate);
      final latestSteps = await repo.getLatestMeasurement(HealthMetricType.steps);

      expect(latestHr?.value, 75.0);
      expect(latestHr?.unit, 'bpm');
      expect(latestSteps?.value, 1250.0);
      expect(latestSteps?.unit, 'steps');

      repo.dispose();
      await controller.close();
      await db.close();
    });

    test('stores and returns SpO2 spot measurements independently', () async {
      final db = HealthDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      final controller = StreamController<HealthMeasurement>();
      final repo = SamsungHealthRepository(
        dataStream: controller.stream,
        database: db,
      );

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
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final latestSpO2 = await repo.getLatestMeasurement(HealthMetricType.spo2);
      expect(latestSpO2?.value, 99.0);
      expect(latestSpO2?.unit, '%');

      repo.dispose();
      await controller.close();
      await db.close();
    });

    test('history honors limit and maxHistorySize bounding', () async {
      final db = HealthDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      final repo = SamsungHealthRepository(
        maxHistorySize: 5,
        database: db,
      );

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

      repo.dispose();
      await db.close();
    });
  });
}
