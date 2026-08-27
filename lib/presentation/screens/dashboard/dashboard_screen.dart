import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/health_metric_type.dart';
import '../../providers/health_providers.dart';
import '../../widgets/demo_data_banner.dart';
import '../../widgets/empty_state_card.dart';
import '../../widgets/metric_summary_card.dart';

/// Dashboard (home) tab.
///
/// Shows a quick summary of the user's most relevant metrics. No fake
/// numbers are shown — until real measurements exist (Milestone 3+),
/// each summary is an honest "no data yet" placeholder.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final heartRate = ref.watch(
      latestMeasurementProvider(HealthMetricType.heartRate),
    );
    final steps = ref.watch(
      latestMeasurementProvider(HealthMetricType.steps),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const DemoDataBanner(),
          const SizedBox(height: 12),
          heartRate.when(
            data: (measurement) => measurement == null
                ? const EmptyStateCard(
                    icon: Icons.favorite_outline,
                    title: 'Heart rate',
                    message: 'No measurements yet. Connect a Galaxy Watch '
                        'to start collecting data.',
                  )
                : MetricSummaryCard(
                    icon: Icons.favorite_outline,
                    title: 'Heart rate',
                    measurement: measurement,
                  ),
            loading: () => const _LoadingCard(title: 'Heart rate'),
            error: (error, stackTrace) => const EmptyStateCard(
              icon: Icons.favorite_outline,
              title: 'Heart rate',
              message: "Couldn't load heart rate right now.",
            ),
          ),
          const SizedBox(height: 12),
          steps.when(
            data: (measurement) => measurement == null
                ? const EmptyStateCard(
                    icon: Icons.directions_walk,
                    title: 'Activity',
                    message: 'No activity data yet.',
                  )
                : MetricSummaryCard(
                    icon: Icons.directions_walk,
                    title: 'Activity',
                    measurement: measurement,
                  ),
            loading: () => const _LoadingCard(title: 'Activity'),
            error: (error, stackTrace) => const EmptyStateCard(
              icon: Icons.directions_walk,
              title: 'Activity',
              message: "Couldn't load activity data right now.",
            ),
          ),
          const SizedBox(height: 12),
          const EmptyStateCard(
            icon: Icons.spa_outlined,
            title: 'Wellness insight',
            message: 'Insights appear once enough history is available '
                'to establish your personal baseline.',
          ),
        ],
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 16),
            Text('Loading $title…'),
          ],
        ),
      ),
    );
  }
}

