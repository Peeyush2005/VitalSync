import 'package:flutter/material.dart';

/// Placeholder splash screen.
///
/// Serves as the app's initial route while the foundation (theming,
/// routing, dependency wiring) is established. Real splash behavior
/// (branding, auth-state check, navigation) is implemented in the
/// UI/screens milestone.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text('VitalSync'),
      ),
    );
  }
}
