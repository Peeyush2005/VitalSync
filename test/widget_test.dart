// Basic smoke test verifying the VitalSync app shell builds and renders
// its initial route without error.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vitalsync/app.dart';

void main() {
  testWidgets('VitalSyncApp builds and shows the splash screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: VitalSyncApp()),
    );
    await tester.pumpAndSettle();

    expect(find.text('VitalSync'), findsOneWidget);
  });
}

