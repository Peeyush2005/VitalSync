import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../analytics/personal_baseline_engine.dart';
import '../../../analytics/trend_engine.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/health_metric_type.dart';
import '../../providers/health_providers.dart';
import '../../widgets/demo_data_banner.dart';

/// Insights tab — AI and analytics-derived personal baselines and trend intelligence.
class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hrTrend = ref.watch(metricTrendProvider(HealthMetricType.heartRate));
    final hrBaseline = ref.watch(personalBaselineProvider(HealthMetricType.heartRate));

    final stepsTrend = ref.watch(metricTrendProvider(HealthMetricType.steps));
    final stepsBaseline = ref.watch(personalBaselineProvider(HealthMetricType.steps));

    final spo2Trend = ref.watch(metricTrendProvider(HealthMetricType.spo2));
    final spo2Baseline = ref.watch(personalBaselineProvider(HealthMetricType.spo2));

    return Scaffold(
      appBar: AppBar(title: const Text('Insights & Trends')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          const DemoDataBanner(),
          const SizedBox(height: 12),

          // Header Intelligence Banner
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppTheme.wellnessColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: AppTheme.wellnessColor.withValues(alpha: 0.25),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.wellnessColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    color: AppTheme.wellnessColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Personal Baseline Intelligence',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Statistical trend evaluation against your personal history',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 1. Heart Rate Trend Card
          _TrendCard(
            title: 'Heart Rate',
            icon: Icons.favorite_outline,
            accentColor: AppTheme.heartRateColor,
            trend: hrTrend,
            baseline: hrBaseline,
          ),
          const SizedBox(height: 12),

          // 2. Activity / Steps Trend Card
          _TrendCard(
            title: 'Activity & Steps',
            icon: Icons.directions_walk,
            accentColor: AppTheme.stepsColor,
            trend: stepsTrend,
            baseline: stepsBaseline,
          ),
          const SizedBox(height: 12),

          // 3. SpO2 Trend Card
          _TrendCard(
            title: 'Blood Oxygen (SpO2)',
            icon: Icons.water_drop_outlined,
            accentColor: AppTheme.spo2Color,
            trend: spo2Trend,
            baseline: spo2Baseline,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({
    required this.title,
    required this.icon,
    required this.accentColor,
    required this.trend,
    required this.baseline,
  });

  final String title;
  final IconData icon;
  final Color accentColor;
  final AsyncValue<MetricTrend> trend;
  final PersonalBaseline baseline;

  IconData _directionIcon(TrendDirection direction) {
    switch (direction) {
      case TrendDirection.stable:
        return Icons.trending_flat;
      case TrendDirection.increasing:
        return Icons.trending_up;
      case TrendDirection.decreasing:
        return Icons.trending_down;
      case TrendDirection.suddenShift:
        return Icons.bolt;
      case TrendDirection.repeatedDeviation:
        return Icons.alt_route;
      case TrendDirection.insufficientData:
        return Icons.hourglass_empty;
    }
  }

  Color _directionColor(TrendDirection direction) {
    switch (direction) {
      case TrendDirection.stable:
        return const Color(0xFF10B981); // Emerald
      case TrendDirection.increasing:
      case TrendDirection.decreasing:
        return const Color(0xFFF59E0B); // Amber
      case TrendDirection.suddenShift:
      case TrendDirection.repeatedDeviation:
        return const Color(0xFFEF4444); // Coral Red
      case TrendDirection.insufficientData:
        return const Color(0xFF94A3B8); // Slate
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: switch (trend) {
          AsyncData(:final value) => _buildContent(context, value),
          AsyncError() => _buildError(context),
          _ => _buildLoading(context),
        },
      ),
    );
  }

  Widget _buildLoading(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(context, null),
        const SizedBox(height: 12),
        Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: accentColor,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Analyzing $title trends…',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildError(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(context, null),
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 16,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Trend analysis is temporarily unavailable. Your data is still being recorded.',
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, MetricTrend? trend) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
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
        Expanded(
          child: Text(
            title,
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (trend != null) _buildDirectionBadge(trend.direction),
      ],
    );
  }

  Widget _buildDirectionBadge(TrendDirection direction) {
    final dirColor = _directionColor(direction);
    final dirIcon = _directionIcon(direction);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: dirColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: dirColor.withValues(alpha: 0.25),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(dirIcon, color: dirColor, size: 14),
          const SizedBox(width: 4),
          Text(
            direction.label,
            style: TextStyle(
              color: dirColor,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, MetricTrend trend) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header Row: Icon + Title + Direction Badge
        _buildHeader(context, trend),
        const SizedBox(height: 12),

        // Headline & Explanation Message
        Text(
          trend.headline,
          style: textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          trend.message,
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 10),

        // Baseline Status Subtitle / Pill
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                Icons.speed,
                size: 13,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  baseline.statusMessage,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
