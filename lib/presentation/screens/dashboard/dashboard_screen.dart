import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/health_metric_type.dart';
import '../../../data/models/watch_connection_state.dart';
import '../../providers/health_providers.dart';
import '../../providers/watch_connection_provider.dart';
import '../../widgets/demo_data_banner.dart';
import '../../widgets/empty_state_card.dart';
import '../../widgets/metric_summary_card.dart';
import '../../widgets/watch_status_card.dart';

/// Dashboard (home) tab.
///
/// Shows a modern, data-rich summary of the user's biometric streams and
/// watch connection status.
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
    final spo2 = ref.watch(
      latestMeasurementProvider(HealthMetricType.spo2),
    );
    final watchConnection = ref.watch(watchConnectionProvider);
    final connectionState =
        watchConnection.value ?? WatchConnectionState.disconnected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Check Connection',
            onPressed: () {
              ref.read(watchHealthBridgeProvider).requestConnect();
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // 1. Galaxy Watch Hardware Status Banner
          WatchStatusCard(state: connectionState),
          const SizedBox(height: 12),

          // 2. Demo Banner when disconnected
          if (!connectionState.isActive) ...[
            const DemoDataBanner(),
            const SizedBox(height: 12),
          ],

          // 3. Section Header
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
            child: Row(
              children: [
                Text(
                  'REAL-TIME BIOMETRICS',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

          // 4. Heart Rate Card
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
            loading: () => const _LoadingCard(
              title: 'Heart rate',
              accentColor: AppTheme.heartRateColor,
            ),
            error: (error, stackTrace) => const EmptyStateCard(
              icon: Icons.favorite_outline,
              title: 'Heart rate',
              message: "Couldn't load heart rate right now.",
            ),
          ),
          const SizedBox(height: 12),

          // 5. Steps / Activity Card
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
            loading: () => const _LoadingCard(
              title: 'Activity',
              accentColor: AppTheme.stepsColor,
            ),
            error: (error, stackTrace) => const EmptyStateCard(
              icon: Icons.directions_walk,
              title: 'Activity',
              message: "Couldn't load activity data right now.",
            ),
          ),
          const SizedBox(height: 12),

          // 6. Blood Oxygen (SpO2) Card
          spo2.when(
            data: (measurement) => measurement == null
                ? const EmptyStateCard(
                    icon: Icons.water_drop_outlined,
                    title: 'Blood oxygen (SpO2)',
                    message: 'No SpO2 spot measurement yet. Take an on-demand '
                        'reading from your Galaxy Watch.',
                  )
                : MetricSummaryCard(
                    icon: Icons.water_drop_outlined,
                    title: 'Blood oxygen (SpO2)',
                    measurement: measurement,
                  ),
            loading: () => const _LoadingCard(
              title: 'Blood oxygen',
              accentColor: AppTheme.spo2Color,
            ),
            error: (error, stackTrace) => const EmptyStateCard(
              icon: Icons.water_drop_outlined,
              title: 'Blood oxygen (SpO2)',
              message: "Couldn't load SpO2 data right now.",
            ),
          ),
          const SizedBox(height: 12),

          // 7. Wellness Insight Card
          const EmptyStateCard(
            icon: Icons.spa_outlined,
            title: 'Wellness insight',
            message: 'Insights appear once enough history is available '
                'to establish your personal baseline.',
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard({
    required this.title,
    this.accentColor,
  });

  final String title;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? Theme.of(context).colorScheme.primary;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            const SizedBox(width: 16),
            Text(
              'Loading $title…',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
