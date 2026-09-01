import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalsync/analytics/anomaly_engine.dart';
import 'package:vitalsync/data/models/activity_state.dart';
import 'package:vitalsync/data/models/health_data_source.dart';
import 'package:vitalsync/data/models/health_measurement.dart';
import 'package:vitalsync/data/models/health_metric_type.dart';
import 'package:vitalsync/presentation/widgets/metric_summary_card.dart';

void main() {
  final measurement = HealthMeasurement(
    id: 'hr_1',
    userId: 'u1',
    type: HealthMetricType.heartRate,
    value: 95.0,
    unit: 'bpm',
    timestamp: DateTime.now(),
    source: HealthDataSource.galaxyWatch,
    activityState: ActivityState.resting,
    qualityScore: 0.95,
    confidence: 0.95,
  );

  Widget buildCard({AnomalyResult? anomaly}) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: MetricSummaryCard(
            icon: Icons.favorite_outline,
            title: 'Heart rate',
            measurement: measurement,
            anomaly: anomaly,
          ),
        ),
      ),
    );
  }

  AnomalyResult makeAnomaly({
    required bool isOngoing,
    AnomalySeverity severity = AnomalySeverity.moderate,
  }) {
    final now = DateTime.now();
    return AnomalyResult(
      type: HealthMetricType.heartRate,
      isAnomaly: true,
      severity: severity,
      deviation: 19.0,
      confidence: 0.85,
      headline: 'Unusual heart rate reading',
      message:
          'Your heart rate reading of 95 bpm is above your usual range '
          '(60–76 bpm). A single reading outside your usual range is often '
          'nothing — worth monitoring.',
      reasons: const ['outside_expected_range'],
      anomalyKey: 'heartRate:high',
      isOngoing: isOngoing,
      firstDetectedAt: now.subtract(const Duration(minutes: 10)),
      detectedAt: now,
    );
  }

  testWidgets('shows non-diagnostic anomaly banner when an anomaly is active',
      (tester) async {
    await tester.pumpWidget(buildCard(anomaly: makeAnomaly(isOngoing: false)));
    await tester.pumpAndSettle();

    expect(find.text('Unusual heart rate reading'), findsOneWidget);
    expect(find.textContaining('worth monitoring'), findsOneWidget);
    expect(find.textContaining('above your usual range'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    // Not ongoing => no Ongoing chip.
    expect(find.text('Ongoing'), findsNothing);
  });

  testWidgets('shows Ongoing chip for a sustained (ongoing) anomaly',
      (tester) async {
    await tester.pumpWidget(buildCard(anomaly: makeAnomaly(isOngoing: true)));
    await tester.pumpAndSettle();

    expect(find.text('Ongoing'), findsOneWidget);
  });

  testWidgets('no anomaly banner when the evaluation is not an anomaly',
      (tester) async {
    final now = DateTime.now();
    final normal = AnomalyResult.gated(
      HealthMetricType.heartRate,
      detectedAt: now,
      reasons: const ['within_expected_range'],
    );

    await tester.pumpWidget(buildCard(anomaly: normal));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    expect(find.textContaining('worth monitoring'), findsNothing);
  });

  testWidgets('no anomaly banner when anomaly is null (still evaluating)',
      (tester) async {
    await tester.pumpWidget(buildCard(anomaly: null));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
  });
}
