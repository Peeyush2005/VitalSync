import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalsync/data/models/watch_connection_state.dart';
import 'package:vitalsync/presentation/widgets/watch_status_card.dart';

void main() {
  testWidgets('shows "Not connected" for the disconnected state', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WatchStatusCard(state: WatchConnectionState.disconnected),
        ),
      ),
    );

    expect(find.text('Galaxy Watch'), findsOneWidget);
    expect(find.text('Not connected'), findsOneWidget);
  });

  testWidgets('shows "Connected" for the connected state', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WatchStatusCard(state: WatchConnectionState.connected),
        ),
      ),
    );

    expect(find.text('Connected'), findsOneWidget);
  });

  testWidgets('shows staleness indicator when connected with lastUpdated', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WatchStatusCard(
            state: WatchConnectionState.connected,
            lastUpdated: DateTime.now().subtract(const Duration(seconds: 15)),
          ),
        ),
      ),
    );

    expect(find.text('Galaxy Watch'), findsOneWidget);
    expect(find.textContaining('Connected • Updated 15s ago'), findsOneWidget);
  });
}
