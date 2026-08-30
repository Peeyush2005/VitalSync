import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_theme.dart';

/// Profile tab — account, paired hardware, and privacy controls.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // User Card
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryTeal.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.person,
                      color: AppTheme.primaryTeal,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Local User Profile',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'On-device biometric storage',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Hardware & Settings Card
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.watch_outlined, color: AppTheme.primaryTeal),
                  title: const Text('Paired Devices', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Samsung Galaxy Watch4 (SM-R870)'),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () {},
                ),
                Divider(height: 1, color: colorScheme.outline.withValues(alpha: 0.2)),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined, color: AppTheme.stepsColor),
                  title: const Text('Privacy & Health Data', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('100% on-device local storage'),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () {},
                ),
                Divider(height: 1, color: colorScheme.outline.withValues(alpha: 0.2)),
                ListTile(
                  leading: const Icon(Icons.notifications_outlined, color: AppTheme.spo2Color),
                  title: const Text('Notifications', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Heart rate baseline alerts'),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () {},
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Sign out / Reset
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: Icon(Icons.logout, color: colorScheme.error),
              title: Text(
                'Sign out',
                style: TextStyle(
                  color: colorScheme.error,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onTap: () => context.go(AppRoutes.login),
            ),
          ),
        ],
      ),
    );
  }
}
