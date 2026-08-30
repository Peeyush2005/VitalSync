import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/health_measurement.dart';
import '../../../data/models/health_metric_type.dart';
import '../../providers/health_providers.dart';
import '../../widgets/demo_data_banner.dart';
import '../../widgets/empty_state_card.dart';

/// Health Metrics tab — detailed per-metric history and quality tracking.
class HealthMetricsScreen extends ConsumerWidget {
  const HealthMetricsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Health Metrics')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: const [
          DemoDataBanner(),
          SizedBox(height: 14),
          _MetricHistorySection(
            title: 'Heart rate',
            icon: Icons.favorite_outline,
            type: HealthMetricType.heartRate,
            accentColor: AppTheme.heartRateColor,
          ),
          SizedBox(height: 14),
          _MetricHistorySection(
            title: 'Activity',
            icon: Icons.directions_run_outlined,
            type: HealthMetricType.steps,
            accentColor: AppTheme.stepsColor,
          ),
          SizedBox(height: 14),
          _MetricHistorySection(
            title: 'Blood oxygen (SpO2)',
            icon: Icons.water_drop_outlined,
            type: HealthMetricType.spo2,
            accentColor: AppTheme.spo2Color,
          ),
          SizedBox(height: 14),
          EmptyStateCard(
            icon: Icons.verified_outlined,
            title: 'Measurement quality',
            message: 'Quality and confidence scores are shown next to '
                'each reading above. A full data-quality dashboard '
                'arrives in a later milestone.',
          ),
          SizedBox(height: 16),
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
    required this.accentColor,
  });

  final String title;
  final IconData icon;
  final HealthMetricType type;
  final Color accentColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(measurementHistoryProvider(type));
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.25),
                      width: 1,
                    ),
                  ),
                  child: Icon(icon, color: accentColor, size: 18),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            history.when(
              data: (measurements) => measurements.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'No data yet.',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                    )
                  : Column(
                      children: measurements
                          .take(5)
                          .map((m) => _MeasurementRow(
                                measurement: m,
                                accentColor: accentColor,
                              ))
                          .toList(growable: false),
                    ),
              loading: () => Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                    ),
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
  const _MeasurementRow({
    required this.measurement,
    required this.accentColor,
  });

  final HealthMeasurement measurement;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final quality = measurement.qualityScore;
    final colorScheme = Theme.of(context).colorScheme;

    final formattedValue = measurement.type == HealthMetricType.steps
        ? measurement.value.toInt().toString()
        : measurement.value.toStringAsFixed(0);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Text(
                  formattedValue,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  measurement.unit,
                  style: TextStyle(
                    color: accentColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${measurement.timestamp.hour.toString().padLeft(2, '0')}:'
            '${measurement.timestamp.minute.toString().padLeft(2, '0')}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (quality != null) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${(quality * 100).round()}%',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: accentColor,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
