import 'package:flutter/material.dart';

import '../../widgets/empty_state_card.dart';

/// History tab — chronological timeline of past measurements.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          EmptyStateCard(
            icon: Icons.timeline_outlined,
            title: 'No history yet',
            message: 'Your measurement timeline will appear here once '
                'data has been collected.',
          ),
        ],
      ),
    );
  }
}
