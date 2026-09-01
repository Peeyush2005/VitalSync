import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vitalsync/data/local/health_database.dart';
import 'package:vitalsync/data/models/activity_state.dart';
import 'package:vitalsync/data/models/health_data_source.dart';
import 'package:vitalsync/data/models/health_measurement.dart';
import 'package:vitalsync/data/models/health_metric_type.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late HealthDatabase db;

  setUp(() {
    db = HealthDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('HealthDatabase persistence', () {
    test('inserts and retrieves latest measurement', () async {
      final now = DateTime(2026, 8, 28, 10, 0, 0);
      final m1 = HealthMeasurement(
        id: 'hr_1',
        userId: 'u1',
        type: HealthMetricType.heartRate,
        value: 72.0,
        unit: 'bpm',
        timestamp: now,
        source: HealthDataSource.galaxyWatch,
        activityState: ActivityState.resting,
        qualityScore: 1.0,
        confidence: 0.95,
      );

      await db.insertMeasurement(m1);

      final latest = await db.getLatestMeasurement(HealthMetricType.heartRate);
      expect(latest, isNotNull);
      expect(latest?.id, equals('hr_1'));
      expect(latest?.value, equals(72.0));
      expect(latest?.activityState, equals(ActivityState.resting));
      expect(latest?.qualityScore, equals(1.0));
      expect(latest?.confidence, equals(0.95));
    });

    test('retrieves measurements in time range with activity and quality filtering', () async {
      final base = DateTime(2026, 8, 28, 10, 0, 0);

      final measurements = [
        HealthMeasurement(
          id: 'hr_1',
          userId: 'u1',
          type: HealthMetricType.heartRate,
          value: 65.0,
          unit: 'bpm',
          timestamp: base.subtract(const Duration(minutes: 10)),
          source: HealthDataSource.galaxyWatch,
          activityState: ActivityState.resting,
          qualityScore: 0.95,
        ),
        HealthMeasurement(
          id: 'hr_2',
          userId: 'u1',
          type: HealthMetricType.heartRate,
          value: 120.0,
          unit: 'bpm',
          timestamp: base.subtract(const Duration(minutes: 5)),
          source: HealthDataSource.galaxyWatch,
          activityState: ActivityState.walking,
          qualityScore: 0.90,
        ),
        HealthMeasurement(
          id: 'hr_3',
          userId: 'u1',
          type: HealthMetricType.heartRate,
          value: 68.0,
          unit: 'bpm',
          timestamp: base,
          source: HealthDataSource.galaxyWatch,
          activityState: ActivityState.resting,
          qualityScore: 0.40, // Low quality
        ),
      ];

      await db.insertBatch(measurements);

      // Query only resting HR with min quality 0.80
      final restingHighQuality = await db.getMeasurements(
        HealthMetricType.heartRate,
        activityState: ActivityState.resting,
        minQualityScore: 0.80,
      );

      expect(restingHighQuality.length, equals(1));
      expect(restingHighQuality.first.id, equals('hr_1'));
      expect(restingHighQuality.first.value, equals(65.0));

      // Query with time bounds
      final inWindow = await db.getMeasurements(
        HealthMetricType.heartRate,
        startTime: base.subtract(const Duration(minutes: 6)),
        endTime: base,
      );

      expect(inWindow.length, equals(2));
      expect(inWindow.map((m) => m.id), containsAll(['hr_2', 'hr_3']));
    });

    test('counts matching records correctly', () async {
      final base = DateTime(2026, 8, 28, 10, 0, 0);
      final steps = [
        HealthMeasurement(
          id: 's_1',
          userId: 'u1',
          type: HealthMetricType.steps,
          value: 100.0,
          unit: 'steps',
          timestamp: base.subtract(const Duration(hours: 1)),
          source: HealthDataSource.galaxyWatch,
        ),
        HealthMeasurement(
          id: 's_2',
          userId: 'u1',
          type: HealthMetricType.steps,
          value: 500.0,
          unit: 'steps',
          timestamp: base,
          source: HealthDataSource.galaxyWatch,
        ),
      ];

      await db.insertBatch(steps);
      final count = await db.countMeasurements(HealthMetricType.steps);
      expect(count, equals(2));

      final hrCount = await db.countMeasurements(HealthMetricType.heartRate);
      expect(hrCount, equals(0));
    });
  });
}
