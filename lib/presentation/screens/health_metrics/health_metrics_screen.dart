import 'package:flutter/material.dart';

import '../../widgets/empty_state_card.dart';

/// Health Metrics tab — detailed per-metric views.
class HealthMetricsScreen extends StatelessWidget {
  const HealthMetricsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Health Metrics')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          EmptyStateCard(
            icon: Icons.favorite_outline,
            title: 'Heart rate',
            message: 'No data yet.',
          ),
          SizedBox(height: 12),
          EmptyStateCard(
            icon: Icons.directions_run_outlined,
            title: 'Activity state',
            message: 'No data yet.',
          ),
          SizedBox(height: 12),
          EmptyStateCard(
            icon: Icons.verified_outlined,
            title: 'Measurement quality',
            message: 'Quality and confidence scores appear once '
                'measurements are collected.',
          ),
        ],
      ),
    );
  }
}
