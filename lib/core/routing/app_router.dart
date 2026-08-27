import 'package:go_router/go_router.dart';

import '../../presentation/screens/splash/splash_screen.dart';

/// Route path constants used across the app.
///
/// Additional routes (onboarding, login, register, dashboard, health
/// metrics, insights, history, profile) are added in later milestones.
abstract final class AppRoutes {
  static const String splash = '/';
}

/// Top-level router configuration for VitalSync.
final GoRouter appRouter = GoRouter(
  initialLocation: AppRoutes.splash,
  routes: [
    GoRoute(
      path: AppRoutes.splash,
      builder: (context, state) => const SplashScreen(),
    ),
  ],
);
