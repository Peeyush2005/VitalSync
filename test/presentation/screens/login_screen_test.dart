import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vitalsync/presentation/screens/auth/login_screen.dart';

void main() {
  testWidgets('shows validation errors when submitting empty fields', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: LoginScreen()),
    );

    await tester.tap(find.text('Log in'));
    await tester.pump();

    expect(find.text('Enter your email'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);
  });

  testWidgets('rejects an email without @', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: LoginScreen()),
    );

    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'invalid');
    await tester.tap(find.text('Log in'));
    await tester.pump();

    expect(find.text('Enter a valid email'), findsOneWidget);
  });
}
