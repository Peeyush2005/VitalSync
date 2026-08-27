import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'fake_health_repository.dart';
import 'health_repository.dart';

/// Provides the active [HealthRepository] implementation.
///
/// Currently always resolves to [FakeHealthRepository]. A
/// `SamsungHealthRepository` exists as a not-yet-functional stub (see its
/// doc comment for why); swapping to it once real Galaxy Watch
/// integration is complete only requires changing this provider - no UI
/// code should need to change.
final healthRepositoryProvider = Provider<HealthRepository>((ref) {
  return FakeHealthRepository();
});

