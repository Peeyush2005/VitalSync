import 'package:flutter/material.dart';

import '../../data/models/health_measurement.dart';

/// Displays a single [HealthMeasurement] with its value, recency, source,
/// and quality/confidence — never just a bare number, so the user always
/// has enough context to judge how much to trust it.
class MetricSummaryCard extends StatelessWidget {
  const MetricSummaryCard({
    super.key,
    required this.icon,
    required this.title,
    required this.measurement,
  });

  final IconData icon;
  final String title;
  final HealthMeasurement measurement;

  String _relativeTime(DateTime timestamp) {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    return '${diff.inDays} d ago';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final quality = measurement.qualityScore;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(title, style: textTheme.titleMedium),
                const Spacer(),
                Text(
                  _relativeTime(measurement.timestamp),
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '${measurement.value.toStringAsFixed(0)} ${measurement.unit}',
              style: textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                Chip(
                  label: Text(measurement.source.label),
                  visualDensity: VisualDensity.compact,
                ),
                if (measurement.activityState != null)
                  Chip(
                    label: Text(measurement.activityState!.label),
                    visualDensity: VisualDensity.compact,
                  ),
                if (quality != null)
                  Chip(
                    label: Text('Quality ${(quality * 100).round()}%'),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
