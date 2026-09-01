import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalsync/data/models/watch_connection_state.dart';
import 'package:vitalsync/data/repositories/fake_health_repository.dart';
import 'package:vitalsync/data/repositories/health_repository.dart';
import 'package:vitalsync/data/repositories/health_repository_provider.dart';
import 'package:vitalsync/presentation/providers/watch_connection_provider.dart';
import 'package:vitalsync/presentation/screens/dashboard/dashboard_screen.dart';

void main() {
  testWidgets('shows demo banner and metric cards once data loads', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          healthRepositoryProvider.overrideWithValue(
            FakeHealthRepository() as HealthRepository,
          ),
          watchConnectionProvider.overrideWith(
            (ref) => Stream.value(WatchConnectionState.disconnected),
          ),
        ],
        child: const MaterialApp(home: DashboardScreen()),
      ),
    );

    // Providers resolve asynchronously.
    await tester.pumpAndSettle();

    expect(find.text('Galaxy Watch'), findsOneWidget);
    expect(find.text('Not connected'), findsOneWidget);
    expect(find.text('Activity Context'), findsOneWidget);
    expect(find.textContaining('simulated demo data'), findsOneWidget);
    expect(find.text('Heart rate'), findsOneWidget);
    expect(find.textContaining('bpm'), findsWidgets);

    // Scroll to ensure SpO2 card is built in standard test viewport
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();

    expect(find.text('Blood oxygen (SpO2)'), findsOneWidget);
    expect(find.textContaining('%'), findsWidgets);
  });
}

