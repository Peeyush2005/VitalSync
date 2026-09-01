import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalsync/analytics/activity_classifier.dart';
import 'package:vitalsync/data/models/activity_state.dart';
import 'package:vitalsync/presentation/widgets/activity_context_card.dart';

void main() {
  testWidgets('renders ActivityContextCard with state and confidence', (
    WidgetTester tester,
  ) async {
    const result = ActivityClassificationResult(
      state: ActivityState.walking,
      confidence: 0.90,
      reasons: ['steady_walking_cadence'],
      estimatedCadenceSpm: 84.0,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ActivityContextCard(result: result),
        ),
      ),
    );

    expect(find.text('Activity Context'), findsOneWidget);
    expect(find.text('Walking'), findsOneWidget);
    expect(find.text('Confidence 90%'), findsOneWidget);
    expect(find.text('84 steps/min'), findsOneWidget);
    expect(find.text('Steady walking cadence detected'), findsOneWidget);
  });

  testWidgets('renders Resting state properly', (WidgetTester tester) async {
    const result = ActivityClassificationResult(
      state: ActivityState.resting,
      confidence: 0.95,
      reasons: ['resting_heart_rate_range'],
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ActivityContextCard(result: result),
        ),
      ),
    );

    expect(find.text('Activity Context'), findsOneWidget);
    expect(find.text('Resting'), findsOneWidget);
    expect(find.text('Confidence 95%'), findsOneWidget);
    expect(find.text('Low movement • Normal resting biometrics'), findsOneWidget);
  });
}
