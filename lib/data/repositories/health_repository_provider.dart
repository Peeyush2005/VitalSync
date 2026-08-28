import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../presentation/providers/watch_connection_provider.dart';
import 'fake_health_repository.dart';
import 'health_repository.dart';
import 'samsung_health_repository.dart';

/// Provides the active [SamsungHealthRepository] instance wired to [WatchHealthBridge].
final samsungHealthRepositoryProvider = Provider<SamsungHealthRepository>((ref) {
  final bridge = ref.watch(watchHealthBridgeProvider);
  final repository = SamsungHealthRepository(bridge: bridge);
  ref.onDispose(() => repository.dispose());
  return repository;
});

/// Provides the active [HealthRepository] implementation.
///
/// Dynamic Resolution:
/// - When a real Galaxy Watch is connected/measuring ([watchConnectionProvider.isActive]),
///   this provides the real [SamsungHealthRepository].
/// - When no watch is connected, this falls back to [FakeHealthRepository], which
///   is explicitly tagged with `HealthDataSource.simulated` and accompanied by
///   the `DemoDataBanner` on the dashboard.
final healthRepositoryProvider = Provider<HealthRepository>((ref) {
  final watchConnection = ref.watch(watchConnectionProvider);
  final connectionState = watchConnection.value;

  if (connectionState != null && connectionState.isActive) {
    return ref.watch(samsungHealthRepositoryProvider);
  }
  return FakeHealthRepository();
});
