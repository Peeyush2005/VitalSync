import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vitalsync/presentation/screens/onboarding/onboarding_screen.dart';

void main() {
  testWidgets('advances through pages and finishes with Get started', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: OnboardingScreen()),
    );

    expect(find.text('Understand your health'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Spot trends early'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Your data stays yours'), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);
  });
}
