import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalsync/data/repositories/fake_health_repository.dart';
import 'package:vitalsync/data/repositories/health_repository.dart';
import 'package:vitalsync/data/repositories/health_repository_provider.dart';
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
        ],
        child: const MaterialApp(home: DashboardScreen()),
      ),
    );

    // Providers resolve asynchronously.
    await tester.pumpAndSettle();

    expect(find.textContaining('simulated demo data'), findsOneWidget);
    expect(find.text('Heart rate'), findsOneWidget);
    expect(find.textContaining('bpm'), findsOneWidget);
  });
}
