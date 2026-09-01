import 'package:flutter/material.dart';

import '../../analytics/activity_classifier.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/activity_state.dart';

/// Card widget displaying the classified real-time physical activity context.
///
/// Features:
/// - Semantic color & squircle icon per [ActivityState].
/// - Calculated state label (Resting, Walking, Active, Exercising, Unknown).
/// - Real confidence score pill and estimated step cadence.
class ActivityContextCard extends StatelessWidget {
  const ActivityContextCard({
    super.key,
    required this.result,
  });

  final ActivityClassificationResult result;

  IconData _iconForState(ActivityState state) {
    switch (state) {
      case ActivityState.resting:
        return Icons.weekend_outlined;
      case ActivityState.walking:
        return Icons.directions_walk;
      case ActivityState.active:
        return Icons.directions_run_outlined;
      case ActivityState.exercising:
        return Icons.fitness_center;
      case ActivityState.sleeping:
        return Icons.bedtime_outlined;
      case ActivityState.unknown:
        return Icons.help_outline;
    }
  }

  Color _colorForState(ActivityState state) {
    switch (state) {
      case ActivityState.resting:
        return AppTheme.primaryTeal;
      case ActivityState.walking:
        return AppTheme.stepsColor;
      case ActivityState.active:
        return const Color(0xFFF59E0B); // Amber
      case ActivityState.exercising:
        return AppTheme.heartRateColor;
      case ActivityState.sleeping:
        return AppTheme.wellnessColor;
      case ActivityState.unknown:
        return const Color(0xFF94A3B8); // Slate
    }
  }

  String _subtitleForState(ActivityState state) {
    switch (state) {
      case ActivityState.resting:
        return 'Low movement • Normal resting biometrics';
      case ActivityState.walking:
        return 'Steady walking cadence detected';
      case ActivityState.active:
        return 'Elevated physical movement & activity';
      case ActivityState.exercising:
        return 'High exertion / cardio activity';
      case ActivityState.sleeping:
        return 'Sustained low-motion rest';
      case ActivityState.unknown:
        return 'Analyzing biometrics for activity context';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final accent = _colorForState(result.state);
    final icon = _iconForState(result.state);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Icon + Title + Confidence Badge
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Activity Context',
                        style: textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        result.state.label,
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: accent.withValues(alpha: 0.25),
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    'Confidence ${(result.confidence * 100).round()}%',
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _subtitleForState(result.state),
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            if (result.estimatedCadenceSpm != null &&
                result.estimatedCadenceSpm! > 0) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.speed,
                      size: 14,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${result.estimatedCadenceSpm!.round()} steps/min',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
