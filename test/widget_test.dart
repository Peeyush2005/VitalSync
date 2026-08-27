// Basic smoke test verifying the VitalSync app shell builds, shows the
// splash screen, and then navigates to onboarding.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vitalsync/app.dart';

void main() {
  testWidgets('VitalSyncApp shows splash then navigates to onboarding', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: VitalSyncApp()),
    );

    // Splash is shown immediately.
    expect(find.text('VitalSync'), findsOneWidget);

    // After the splash delay, it navigates to onboarding.
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    expect(find.text('Understand your health'), findsOneWidget);
  });
}


