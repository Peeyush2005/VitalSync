import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalsync/data/repositories/fake_health_repository.dart';
import 'package:vitalsync/data/repositories/health_repository.dart';
import 'package:vitalsync/data/repositories/health_repository_provider.dart';
import 'package:vitalsync/presentation/screens/insights/insights_screen.dart';

void main() {
  testWidgets('renders InsightsScreen with trend cards and baseline intelligence', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          healthRepositoryProvider.overrideWithValue(
            FakeHealthRepository() as HealthRepository,
          ),
        ],
        child: const MaterialApp(home: InsightsScreen()),
      ),
    );

    // Initial pump & settle to resolve async trend providers
    await tester.pumpAndSettle();

    expect(find.text('Insights & Trends'), findsOneWidget);
    expect(find.text('Personal Baseline Intelligence'), findsOneWidget);
    expect(find.text('Heart Rate'), findsOneWidget);
    expect(find.text('Activity & Steps'), findsOneWidget);

    // Scroll to reveal SpO2 trend card
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();

    expect(find.text('Blood Oxygen (SpO2)'), findsOneWidget);
  });
}
