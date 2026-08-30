import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/watch_connection_state.dart';

/// Shows the Galaxy Watch connection state in an elevated, modern status banner.
class WatchStatusCard extends StatelessWidget {
  const WatchStatusCard({
    super.key,
    required this.state,
    this.lastUpdated,
  });

  final WatchConnectionState state;
  final DateTime? lastUpdated;

  String? _formatLastUpdated() {
    if (lastUpdated == null) return null;
    final diff = DateTime.now().difference(lastUpdated!);
    if (diff.inSeconds < 10) return 'Updated just now';
    if (diff.inSeconds < 60) return 'Updated ${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return 'Updated ${diff.inMinutes}m ago';
    return 'Updated ${diff.inHours}h ago';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isActive = state.isActive;

    final statusColor = switch (state) {
      WatchConnectionState.connected ||
      WatchConnectionState.measuring => AppTheme.stepsColor,
      WatchConnectionState.connecting => Colors.orangeAccent,
      WatchConnectionState.error => colorScheme.error,
      WatchConnectionState.disconnected => colorScheme.onSurfaceVariant,
    };

    final updatedText = isActive ? _formatLastUpdated() : null;
    final statusSubtitle = updatedText != null
        ? '${state.label} • $updatedText'
        : state.label;

    return Container(
      decoration: BoxDecoration(
        color: isActive
            ? AppTheme.stepsColor.withValues(alpha: 0.08)
            : colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isActive
              ? AppTheme.stepsColor.withValues(alpha: 0.3)
              : colorScheme.outline.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          // Watch Icon in Squircle Container
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: isActive
                  ? AppTheme.stepsColor.withValues(alpha: 0.15)
                  : colorScheme.surfaceContainerHigh.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isActive
                    ? AppTheme.stepsColor.withValues(alpha: 0.3)
                    : colorScheme.outline.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: Icon(
              Icons.watch_outlined,
              color: isActive ? AppTheme.stepsColor : colorScheme.onSurfaceVariant,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),

          // Device Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      'Galaxy Watch',
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Galaxy Watch4',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                        boxShadow: isActive
                            ? [
                                BoxShadow(
                                  color: statusColor.withValues(alpha: 0.4),
                                  blurRadius: 4,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        statusSubtitle,
                        style: textTheme.bodyMedium?.copyWith(
                          fontSize: 12,
                          color: isActive
                              ? colorScheme.onSurface
                              : colorScheme.onSurfaceVariant,
                          fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
