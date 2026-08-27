import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalsync/data/models/watch_connection_state.dart';
import 'package:vitalsync/data/watch_bridge/watch_health_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const connectionChannel = EventChannel('com.vitalsync/watch_connection');
  const methodChannel = MethodChannel('com.vitalsync/health_bridge');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockStreamHandler(connectionChannel, null);
    messenger.setMockMethodCallHandler(methodChannel, null);
  });

  test('maps native "disconnected" event to WatchConnectionState.disconnected', () async {
    messenger.setMockStreamHandler(
      connectionChannel,
      MockStreamHandler.inline(
        onListen: (arguments, events) => events.success('disconnected'),
      ),
    );

    final bridge = WatchHealthBridge(
      connectionEventChannel: connectionChannel,
      methodChannel: methodChannel,
    );

    final state = await bridge.connectionState().first;
    expect(state, WatchConnectionState.disconnected);
  });

  test('maps unrecognized native events to WatchConnectionState.error', () async {
    messenger.setMockStreamHandler(
      connectionChannel,
      MockStreamHandler.inline(
        onListen: (arguments, events) => events.success('something_unexpected'),
      ),
    );

    final bridge = WatchHealthBridge(
      connectionEventChannel: connectionChannel,
      methodChannel: methodChannel,
    );

    final state = await bridge.connectionState().first;
    expect(state, WatchConnectionState.error);
  });

  test('requestConnect surfaces a PlatformException instead of crashing', () async {
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      throw PlatformException(
        code: 'UNAVAILABLE',
        message: 'Samsung Health Sensor SDK integration is not implemented yet.',
      );
    });

    final bridge = WatchHealthBridge(
      connectionEventChannel: connectionChannel,
      methodChannel: methodChannel,
    );

    expect(
      () => bridge.requestConnect(),
      throwsA(isA<PlatformException>()),
    );
  });
}
