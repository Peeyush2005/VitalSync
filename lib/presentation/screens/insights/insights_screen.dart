import 'package:flutter/material.dart';

import '../../widgets/empty_state_card.dart';

/// Insights tab — AI/analytics-derived wellness insights.
class InsightsScreen extends StatelessWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Insights')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          EmptyStateCard(
            icon: Icons.lightbulb_outline,
            title: 'No insights yet',
            message: 'VitalSync needs sufficient personal history before '
                'it can identify trends or unusual patterns worth '
                'monitoring.',
          ),
        ],
      ),
    );
  }
}
