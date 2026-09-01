import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/activity_state.dart';
import '../models/health_data_source.dart';
import '../models/health_measurement.dart';
import '../models/health_metric_type.dart';

/// SQLite-backed local persistence engine for [HealthMeasurement] time-series records.
///
/// Features:
/// - Asynchronous, non-blocking inserts with zero UI thread contention.
/// - Fast indexed queries for time-range filtering, activity segmentation, and baseline analysis.
/// - Pluggable [DatabaseFactory] / [Database] instance for test isolation.
class HealthDatabase {
  HealthDatabase({
    Database? database,
    DatabaseFactory? databaseFactory,
    String? databasePath,
  })  : _db = database,
        _customFactory = databaseFactory,
        _customPath = databasePath;

  static const String tableName = 'health_measurements';
  static const int schemaVersion = 1;

  Database? _db;
  final DatabaseFactory? _customFactory;
  final String? _customPath;
  Completer<Database>? _initCompleter;

  /// Returns the open [Database] instance, initializing it if necessary.
  Future<Database> get database async {
    if (_db != null && _db!.isOpen) return _db!;
    if (_initCompleter != null) return _initCompleter!.future;

    final completer = Completer<Database>();
    _initCompleter = completer;

    try {
      final db = await _openDatabase();
      _db = db;
      completer.complete(db);
      return db;
    } catch (e, st) {
      completer.completeError(e, st);
      _initCompleter = null;
      rethrow;
    }
  }

  Future<Database> _openDatabase() async {
    if (_db != null && _db!.isOpen) return _db!;

    final factory = _customFactory ?? databaseFactory;
    final path = _customPath ?? p.join(await factory.getDatabasesPath(), 'vitalsync_health.db');

    return await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE $tableName (
              id TEXT PRIMARY KEY,
              user_id TEXT NOT NULL,
              type TEXT NOT NULL,
              value REAL NOT NULL,
              unit TEXT NOT NULL,
              timestamp INTEGER NOT NULL,
              source TEXT NOT NULL,
              activity_state TEXT,
              quality_score REAL,
              confidence REAL
            )
          ''');

          // Composite indexes for efficient time-series range and baseline queries
          await db.execute('''
            CREATE INDEX idx_measurements_type_timestamp
            ON $tableName(type, timestamp DESC)
          ''');

          await db.execute('''
            CREATE INDEX idx_measurements_type_activity_timestamp
            ON $tableName(type, activity_state, timestamp DESC)
          ''');
        },
      ),
    );
  }

  /// Inserts or replaces a single [HealthMeasurement] asynchronously.
  Future<void> insertMeasurement(HealthMeasurement measurement) async {
    final db = await database;
    await db.insert(
      tableName,
      _toMap(measurement),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Inserts a batch of measurements inside a single transaction.
  Future<void> insertBatch(List<HealthMeasurement> measurements) async {
    if (measurements.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    for (final m in measurements) {
      batch.insert(
        tableName,
        _toMap(m),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Returns the most recent measurement of [type], or null if none is found.
  Future<HealthMeasurement?> getLatestMeasurement(HealthMetricType type) async {
    final db = await database;
    final rows = await db.query(
      tableName,
      where: 'type = ?',
      whereArgs: [type.name],
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromMap(rows.first);
  }

  /// Queries historical measurements matching criteria, ordered newest-first.
  Future<List<HealthMeasurement>> getMeasurements(
    HealthMetricType type, {
    int? limit,
    DateTime? startTime,
    DateTime? endTime,
    ActivityState? activityState,
    double? minQualityScore,
  }) async {
    final db = await database;
    final whereClauses = <String>['type = ?'];
    final whereArgs = <dynamic>[type.name];

    if (startTime != null) {
      whereClauses.add('timestamp >= ?');
      whereArgs.add(startTime.millisecondsSinceEpoch);
    }

    if (endTime != null) {
      whereClauses.add('timestamp <= ?');
      whereArgs.add(endTime.millisecondsSinceEpoch);
    }

    if (activityState != null) {
      whereClauses.add('activity_state = ?');
      whereArgs.add(activityState.name);
    }

    if (minQualityScore != null) {
      whereClauses.add('(quality_score IS NULL OR quality_score >= ?)');
      whereArgs.add(minQualityScore);
    }

    final rows = await db.query(
      tableName,
      where: whereClauses.join(' AND '),
      whereArgs: whereArgs,
      orderBy: 'timestamp DESC',
      limit: limit,
    );

    return rows.map(_fromMap).toList(growable: false);
  }

  /// Returns count of measurements matching criteria.
  Future<int> countMeasurements(
    HealthMetricType type, {
    DateTime? startTime,
    DateTime? endTime,
    ActivityState? activityState,
    double? minQualityScore,
  }) async {
    final db = await database;
    final whereClauses = <String>['type = ?'];
    final whereArgs = <dynamic>[type.name];

    if (startTime != null) {
      whereClauses.add('timestamp >= ?');
      whereArgs.add(startTime.millisecondsSinceEpoch);
    }

    if (endTime != null) {
      whereClauses.add('timestamp <= ?');
      whereArgs.add(endTime.millisecondsSinceEpoch);
    }

    if (activityState != null) {
      whereClauses.add('activity_state = ?');
      whereArgs.add(activityState.name);
    }

    if (minQualityScore != null) {
      whereClauses.add('(quality_score IS NULL OR quality_score >= ?)');
      whereArgs.add(minQualityScore);
    }

    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM $tableName WHERE ${whereClauses.join(' AND ')}',
      whereArgs,
    );

    if (result.isEmpty) return 0;
    return (result.first['count'] as num?)?.toInt() ?? 0;
  }

  /// Purges all stored measurements.
  Future<void> clearAll() async {
    final db = await database;
    await db.delete(tableName);
  }

  /// Closes database connection.
  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
      _initCompleter = null;
    }
  }

  // --- Serialization ---

  static Map<String, dynamic> _toMap(HealthMeasurement m) {
    return {
      'id': m.id,
      'user_id': m.userId,
      'type': m.type.name,
      'value': m.value,
      'unit': m.unit,
      'timestamp': m.timestamp.millisecondsSinceEpoch,
      'source': m.source.name,
      'activity_state': m.activityState?.name,
      'quality_score': m.qualityScore,
      'confidence': m.confidence,
    };
  }

  static HealthMeasurement _fromMap(Map<String, dynamic> map) {
    final typeStr = map['type'] as String;
    final sourceStr = map['source'] as String;
    final activityStr = map['activity_state'] as String?;

    return HealthMeasurement(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      type: HealthMetricType.values.firstWhere(
        (e) => e.name == typeStr,
        orElse: () => HealthMetricType.heartRate,
      ),
      value: (map['value'] as num).toDouble(),
      unit: map['unit'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      source: HealthDataSource.values.firstWhere(
        (e) => e.name == sourceStr,
        orElse: () => HealthDataSource.galaxyWatch,
      ),
      activityState: activityStr != null
          ? ActivityState.values.firstWhere(
              (e) => e.name == activityStr,
              orElse: () => ActivityState.unknown,
            )
          : null,
      qualityScore: (map['quality_score'] as num?)?.toDouble(),
      confidence: (map['confidence'] as num?)?.toDouble(),
    );
  }
}
