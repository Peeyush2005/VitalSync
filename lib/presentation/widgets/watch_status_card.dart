import 'package:flutter/material.dart';

import '../../data/models/watch_connection_state.dart';

/// Shows the Galaxy Watch connection state, e.g.:
///
/// ```
/// Galaxy Watch
/// ● Connected • Updated just now
/// ```
///
/// or, when no watch is available:
///
/// ```
/// Galaxy Watch
/// ○ Not connected
/// ```
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
    final isActive = state.isActive;
    final dotColor = switch (state) {
      WatchConnectionState.connected ||
      WatchConnectionState.measuring => Colors.green,
      WatchConnectionState.connecting => Colors.orange,
      WatchConnectionState.error => colorScheme.error,
      WatchConnectionState.disconnected => colorScheme.onSurfaceVariant,
    };

    final updatedText = isActive ? _formatLastUpdated() : null;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(Icons.watch_outlined, color: colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Galaxy Watch',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        isActive ? Icons.circle : Icons.circle_outlined,
                        size: 10,
                        color: dotColor,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          updatedText != null
                              ? '${state.label} • $updatedText'
                              : state.label,
                          style: Theme.of(context).textTheme.bodyMedium,
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
      ),
    );
  }
}
