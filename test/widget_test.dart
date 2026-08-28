// Basic smoke test verifying the VitalSync app shell builds, shows the
// splash screen, and then navigates to onboarding.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vitalsync/app.dart';

void main() {
  testWidgets('VitalSyncApp launches directly into dashboard', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: VitalSyncApp()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dashboard'), findsWidgets);
  });
}


