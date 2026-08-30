import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/health_measurement.dart';
import '../../data/models/health_metric_type.dart';

/// Displays a single [HealthMeasurement] with its value, recency, source,
/// and quality/confidence in a modern, health-app inspired card.
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
    if (diff.inSeconds < 15) return 'Just now';
    if (diff.inMinutes < 1) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Color _accentColor(BuildContext context) {
    switch (measurement.type) {
      case HealthMetricType.heartRate:
        return AppTheme.heartRateColor;
      case HealthMetricType.steps:
        return AppTheme.stepsColor;
      case HealthMetricType.spo2:
        return AppTheme.spo2Color;
    }
  }

  double _normalizedProgress() {
    switch (measurement.type) {
      case HealthMetricType.heartRate:
        // Baseline: 40 to 180 bpm
        return ((measurement.value - 40) / (180 - 40)).clamp(0.05, 1.0);
      case HealthMetricType.steps:
        // Daily target: 10,000 steps
        return (measurement.value / 10000.0).clamp(0.02, 1.0);
      case HealthMetricType.spo2:
        // SpO2: 90% to 100%
        return ((measurement.value - 90) / (100 - 90)).clamp(0.05, 1.0);
    }
  }

  String _formatValue() {
    if (measurement.type == HealthMetricType.steps) {
      return measurement.value.toInt().toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (Match m) => '${m[1]},',
      );
    }
    return measurement.value.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final accent = _accentColor(context);
    final quality = measurement.qualityScore;
    final progress = _normalizedProgress();

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row: Squircle Icon + Title + Recency Tag
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(
                      color: accent.withValues(alpha: 0.25),
                      width: 1,
                    ),
                  ),
                  child: Icon(icon, color: accent, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _relativeTime(measurement.timestamp),
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Hero Value Display
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  _formatValue(),
                  style: textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.0,
                    height: 1.1,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  measurement.unit,
                  style: textTheme.titleSmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Mini Visual Progress / Range Bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Stack(
                children: [
                  Container(
                    height: 5,
                    width: double.infinity,
                    color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.6),
                  ),
                  FractionallySizedBox(
                    widthFactor: progress,
                    child: Container(
                      height: 5,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            accent.withValues(alpha: 0.7),
                            accent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Metadata Badges (Source, Activity State, Quality Score)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _BadgePill(
                  label: measurement.source.label,
                  dotColor: accent,
                ),
                if (measurement.activityState != null)
                  _BadgePill(
                    label: measurement.activityState!.label,
                  ),
                if (quality != null)
                  _BadgePill(
                    label: 'Quality ${(quality * 100).round()}%',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BadgePill extends StatelessWidget {
  const _BadgePill({
    required this.label,
    this.dotColor,
  });

  final String label;
  final Color? dotColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.2),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dotColor != null) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
