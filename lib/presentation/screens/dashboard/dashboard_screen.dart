import 'package:flutter/material.dart';

import '../../widgets/empty_state_card.dart';

/// Dashboard (home) tab.
///
/// Shows a quick summary of the user's most relevant metrics. No fake
/// numbers are shown — until real measurements exist (Milestone 3+),
/// each summary is an honest "no data yet" placeholder.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          EmptyStateCard(
            icon: Icons.favorite_outline,
            title: 'Heart rate',
            message: 'No measurements yet. Connect a Galaxy Watch to '
                'start collecting data.',
          ),
          SizedBox(height: 12),
          EmptyStateCard(
            icon: Icons.directions_walk,
            title: 'Activity',
            message: 'No activity data yet.',
          ),
          SizedBox(height: 12),
          EmptyStateCard(
            icon: Icons.spa_outlined,
            title: 'Wellness insight',
            message: 'Insights appear once enough history is available '
                'to establish your personal baseline.',
          ),
        ],
      ),
    );
  }
}
