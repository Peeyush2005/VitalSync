import 'dart:convert';
import 'package:flutter/services.dart';

import '../models/health_data_source.dart';
import '../models/health_measurement.dart';
import '../models/health_metric_type.dart';
import '../models/watch_connection_state.dart';

/// Thin, hardened wrapper around the Flutter <-> native Android platform channels
/// used to communicate with the Galaxy Watch bridge.
///
/// Channels:
/// - MethodChannel (`com.vitalsync/health_bridge`): actions like `requestConnect()`.
/// - EventChannel (`com.vitalsync/watch_connection`): connection state stream.
/// - EventChannel (`com.vitalsync/watch_health_data`): live sensor data JSON stream.
///
/// Data Contract:
/// ```json
/// {
///   "type": "heart_rate",
///   "value": 72,
///   "unit": "bpm",
///   "timestamp": 1724835000000
/// }
/// ```
///
/// Converts live JSON payloads strictly into [HealthMeasurement] models
/// with [HealthDataSource.galaxyWatch]. Never leaks native SDK types into Dart.
class WatchHealthBridge {
  WatchHealthBridge({
    MethodChannel? methodChannel,
    EventChannel? connectionEventChannel,
    EventChannel? dataEventChannel,
  }) : _methodChannel =
           methodChannel ?? const MethodChannel(_methodChannelName),
       _connectionEventChannel =
           connectionEventChannel ?? const EventChannel(_connectionChannelName),
       _dataEventChannel =
           dataEventChannel ?? const EventChannel(_dataChannelName);

  static const _methodChannelName = 'com.vitalsync/health_bridge';
  static const _connectionChannelName = 'com.vitalsync/watch_connection';
  static const _dataChannelName = 'com.vitalsync/watch_health_data';

  final MethodChannel _methodChannel;
  final EventChannel _connectionEventChannel;
  final EventChannel _dataEventChannel;

  /// Live stream of Watch connection state.
  ///
  /// Never throws: any channel errors are caught and yielded as
  /// [WatchConnectionState.error].
  Stream<WatchConnectionState> connectionState() async* {
    try {
      await for (final event
          in _connectionEventChannel.receiveBroadcastStream()) {
        switch (event) {
          case 'connecting':
            yield WatchConnectionState.connecting;
          case 'connected':
            yield WatchConnectionState.connected;
          case 'measuring':
            yield WatchConnectionState.measuring;
          case 'disconnected':
            yield WatchConnectionState.disconnected;
          default:
            yield WatchConnectionState.error;
        }
      }
    } catch (_) {
      yield WatchConnectionState.error;
    }
  }

  /// Live stream of [HealthMeasurement] readings received from the watch.
  ///
  /// Safely handles malformed JSON, missing fields, or ping heartbeats
  /// without throwing exceptions or polluting widget trees with raw maps.
  Stream<HealthMeasurement> healthDataStream() async* {
    try {
      await for (final event in _dataEventChannel.receiveBroadcastStream()) {
        final measurement = _parseMeasurement(event);
        if (measurement != null) {
          yield measurement;
        }
      }
    } catch (_) {
      // Unhappy path: channel error swallowed gracefully to protect UI
    }
  }

  HealthMeasurement? _parseMeasurement(dynamic event) {
    try {
      if (event == null) return null;
      final Map<String, dynamic> data =
          event is String
              ? jsonDecode(event) as Map<String, dynamic>
              : Map<String, dynamic>.from(event as Map);

      final typeStr = data['type'] as String?;
      final dynamic rawValue = data['value'] ?? data['bpm'];
      final timestampRaw = data['timestamp'];

      // Skip heartbeat pings or null/invalid values
      if (rawValue == null || rawValue is! num) {
        return null;
      }

      final HealthMetricType metricType;
      final String unit;

      if (typeStr == 'heart_rate' || typeStr == 'reading') {
        if (rawValue <= 0) return null;
        metricType = HealthMetricType.heartRate;
        unit = (data['unit'] as String?) ?? 'bpm';
      } else if (typeStr == 'steps' || typeStr == 'step_count') {
        if (rawValue < 0) return null;
        metricType = HealthMetricType.steps;
        unit = (data['unit'] as String?) ?? 'steps';
      } else if (typeStr == 'spo2' || typeStr == 'blood_oxygen') {
        if (rawValue <= 0 || rawValue > 100) return null;
        metricType = HealthMetricType.spo2;
        unit = (data['unit'] as String?) ?? '%';
      } else {
        return null;
      }

      final DateTime timestamp =
          timestampRaw is int
              ? DateTime.fromMillisecondsSinceEpoch(timestampRaw)
              : DateTime.now();

      return HealthMeasurement(
        id: 'galaxy_watch_${metricType.name}_${timestamp.millisecondsSinceEpoch}',
        userId: 'local_user',
        type: metricType,
        value: rawValue.toDouble(),
        unit: unit,
        timestamp: timestamp,
        source: HealthDataSource.galaxyWatch,
        qualityScore: 1.0,
        confidence: 1.0,
      );
    } catch (_) {
      // Malformed JSON or corrupted fields gracefully ignored
      return null;
    }
  }

  /// Requests connection / measurement start from native layer.
  Future<void> requestConnect() async {
    await _methodChannel.invokeMethod<void>('connect');
  }
}
