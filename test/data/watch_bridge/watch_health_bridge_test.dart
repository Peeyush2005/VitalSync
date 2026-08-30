import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalsync/data/models/health_data_source.dart';
import 'package:vitalsync/data/models/health_metric_type.dart';
import 'package:vitalsync/data/models/watch_connection_state.dart';
import 'package:vitalsync/data/watch_bridge/watch_health_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const connectionChannel = EventChannel('com.vitalsync/watch_connection');
  const dataChannel = EventChannel('com.vitalsync/watch_health_data');
  const methodChannel = MethodChannel('com.vitalsync/health_bridge');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockStreamHandler(connectionChannel, null);
    messenger.setMockStreamHandler(dataChannel, null);
    messenger.setMockMethodCallHandler(methodChannel, null);
  });

  group('WatchHealthBridge connectionState', () {
    test('maps native events to WatchConnectionState correctly', () async {
      final states = <WatchConnectionState>[];

      messenger.setMockStreamHandler(
        connectionChannel,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            events.success('connecting');
            events.success('connected');
            events.success('measuring');
            events.success('disconnected');
            events.success('unexpected_status');
          },
        ),
      );

      final bridge = WatchHealthBridge(
        connectionEventChannel: connectionChannel,
        dataEventChannel: dataChannel,
        methodChannel: methodChannel,
      );

      await for (final state in bridge.connectionState().take(5)) {
        states.add(state);
      }

      expect(states, [
        WatchConnectionState.connecting,
        WatchConnectionState.connected,
        WatchConnectionState.measuring,
        WatchConnectionState.disconnected,
        WatchConnectionState.error,
      ]);
    });

    test('handles stream error gracefully', () async {
      messenger.setMockStreamHandler(
        connectionChannel,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            events.error(code: '500', message: 'Stream failed');
          },
        ),
      );

      final bridge = WatchHealthBridge(
        connectionEventChannel: connectionChannel,
        dataEventChannel: dataChannel,
        methodChannel: methodChannel,
      );

      final state = await bridge.connectionState().first;
      expect(state, WatchConnectionState.error);
    });
  });

  group('WatchHealthBridge healthDataStream', () {
    test('parses standardized heart_rate JSON into HealthMeasurement', () async {
      final ts = DateTime(2026, 8, 28, 10, 0, 0);
      final jsonPayload = jsonEncode({
        'type': 'heart_rate',
        'value': 74,
        'unit': 'bpm',
        'timestamp': ts.millisecondsSinceEpoch,
      });

      messenger.setMockStreamHandler(
        dataChannel,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            events.success(jsonPayload);
          },
        ),
      );

      final bridge = WatchHealthBridge(
        connectionEventChannel: connectionChannel,
        dataEventChannel: dataChannel,
        methodChannel: methodChannel,
      );

      final measurement = await bridge.healthDataStream().first;
      expect(measurement.type, HealthMetricType.heartRate);
      expect(measurement.value, 74.0);
      expect(measurement.unit, 'bpm');
      expect(measurement.source, HealthDataSource.galaxyWatch);
      expect(measurement.timestamp, ts);
    });

    test('parses standardized steps JSON into HealthMeasurement', () async {
      final ts = DateTime(2026, 8, 28, 10, 0, 0);
      final jsonPayload = jsonEncode({
        'type': 'steps',
        'value': 3420,
        'unit': 'steps',
        'timestamp': ts.millisecondsSinceEpoch,
      });

      messenger.setMockStreamHandler(
        dataChannel,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            events.success(jsonPayload);
          },
        ),
      );

      final bridge = WatchHealthBridge(
        connectionEventChannel: connectionChannel,
        dataEventChannel: dataChannel,
        methodChannel: methodChannel,
      );

      final measurement = await bridge.healthDataStream().first;
      expect(measurement.type, HealthMetricType.steps);
      expect(measurement.value, 3420.0);
      expect(measurement.unit, 'steps');
      expect(measurement.source, HealthDataSource.galaxyWatch);
      expect(measurement.timestamp, ts);
    });

    test('parses standardized spo2 JSON into HealthMeasurement', () async {
      final ts = DateTime(2026, 8, 28, 10, 0, 0);
      final jsonPayload = jsonEncode({
        'type': 'spo2',
        'value': 98,
        'unit': '%',
        'timestamp': ts.millisecondsSinceEpoch,
      });

      messenger.setMockStreamHandler(
        dataChannel,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            events.success(jsonPayload);
          },
        ),
      );

      final bridge = WatchHealthBridge(
        connectionEventChannel: connectionChannel,
        dataEventChannel: dataChannel,
        methodChannel: methodChannel,
      );

      final measurement = await bridge.healthDataStream().first;
      expect(measurement.type, HealthMetricType.spo2);
      expect(measurement.value, 98.0);
      expect(measurement.unit, '%');
      expect(measurement.source, HealthDataSource.galaxyWatch);
      expect(measurement.timestamp, ts);
    });

    test('parses legacy reading format with bpm field', () async {
      final ts = DateTime(2026, 8, 28, 10, 0, 0);
      final jsonPayload = jsonEncode({
        'type': 'reading',
        'bpm': 82,
        'timestamp': ts.millisecondsSinceEpoch,
      });

      messenger.setMockStreamHandler(
        dataChannel,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            events.success(jsonPayload);
          },
        ),
      );

      final bridge = WatchHealthBridge(
        connectionEventChannel: connectionChannel,
        dataEventChannel: dataChannel,
        methodChannel: methodChannel,
      );

      final measurement = await bridge.healthDataStream().first;
      expect(measurement.value, 82.0);
      expect(measurement.source, HealthDataSource.galaxyWatch);
    });

    test('filters out ping heartbeats without emitting measurements', () async {
      final pingPayload = jsonEncode({
        'type': 'ping',
        'value': null,
        'unit': 'bpm',
        'timestamp': 1724835000000,
      });
      final validPayload = jsonEncode({
        'type': 'heart_rate',
        'value': 68,
        'unit': 'bpm',
        'timestamp': 1724835005000,
      });

      messenger.setMockStreamHandler(
        dataChannel,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            events.success(pingPayload);
            events.success(validPayload);
          },
        ),
      );

      final bridge = WatchHealthBridge(
        connectionEventChannel: connectionChannel,
        dataEventChannel: dataChannel,
        methodChannel: methodChannel,
      );

      final measurement = await bridge.healthDataStream().first;
      expect(measurement.value, 68.0);
    });

    test('ignores malformed JSON and corrupted payloads gracefully', () async {
      const corruptPayload = 'NOT_JSON{bad';
      final validPayload = jsonEncode({
        'type': 'heart_rate',
        'value': 70,
        'unit': 'bpm',
        'timestamp': 1724835005000,
      });

      messenger.setMockStreamHandler(
        dataChannel,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            events.success(corruptPayload);
            events.success(validPayload);
          },
        ),
      );

      final bridge = WatchHealthBridge(
        connectionEventChannel: connectionChannel,
        dataEventChannel: dataChannel,
        methodChannel: methodChannel,
      );

      final measurement = await bridge.healthDataStream().first;
      expect(measurement.value, 70.0);
    });
  });

  group('WatchHealthBridge requestConnect', () {
    test('requestConnect surfaces a PlatformException instead of crashing', () async {
      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        throw PlatformException(
          code: 'UNAVAILABLE',
          message: 'Manual connect request triggered.',
        );
      });

      final bridge = WatchHealthBridge(
        connectionEventChannel: connectionChannel,
        dataEventChannel: dataChannel,
        methodChannel: methodChannel,
      );

      expect(
        () => bridge.requestConnect(),
        throwsA(isA<PlatformException>()),
      );
    });
  });
}
