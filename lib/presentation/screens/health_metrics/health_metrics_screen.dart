import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/health_measurement.dart';
import '../../../data/models/health_metric_type.dart';
import '../../providers/health_providers.dart';
import '../../widgets/demo_data_banner.dart';
import '../../widgets/empty_state_card.dart';

/// Health Metrics tab — detailed per-metric views.
class HealthMetricsScreen extends ConsumerWidget {
  const HealthMetricsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Health Metrics')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const DemoDataBanner(),
          const SizedBox(height: 16),
          _MetricHistorySection(
            title: 'Heart rate',
            icon: Icons.favorite_outline,
            type: HealthMetricType.heartRate,
          ),
          const SizedBox(height: 16),
          _MetricHistorySection(
            title: 'Activity',
            icon: Icons.directions_run_outlined,
            type: HealthMetricType.steps,
          ),
          const SizedBox(height: 16),
          const EmptyStateCard(
            icon: Icons.verified_outlined,
            title: 'Measurement quality',
            message: 'Quality and confidence scores are shown next to '
                'each reading above. A full data-quality dashboard '
                'arrives in a later milestone.',
          ),
        ],
      ),
    );
  }
}

class _MetricHistorySection extends ConsumerWidget {
  const _MetricHistorySection({
    required this.title,
    required this.icon,
    required this.type,
  });

  final String title;
  final IconData icon;
  final HealthMetricType type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(measurementHistoryProvider(type));

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            history.when(
              data: (measurements) => measurements.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('No data yet.'),
                    )
                  : Column(
                      children: measurements
                          .take(5)
                          .map((m) => _MeasurementRow(measurement: m))
                          .toList(growable: false),
                    ),
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
              error: (error, stackTrace) => const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text("Couldn't load history right now."),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MeasurementRow extends StatelessWidget {
  const _MeasurementRow({required this.measurement});

  final HealthMeasurement measurement;

  @override
  Widget build(BuildContext context) {
    final quality = measurement.qualityScore;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${measurement.value.toStringAsFixed(0)} ${measurement.unit}',
            ),
          ),
          Text(
            '${measurement.timestamp.hour.toString().padLeft(2, '0')}:'
            '${measurement.timestamp.minute.toString().padLeft(2, '0')}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (quality != null) ...[
            const SizedBox(width: 8),
            Text(
              '${(quality * 100).round()}%',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

