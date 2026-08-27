import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'fake_health_repository.dart';
import 'health_repository.dart';

/// Provides the active [HealthRepository] implementation.
///
/// Currently always resolves to [FakeHealthRepository]. Swapping to a
/// Samsung Health/Galaxy Watch-backed implementation in later milestones
/// only requires changing this provider — no UI code should need to
/// change.
final healthRepositoryProvider = Provider<HealthRepository>((ref) {
  return FakeHealthRepository();
});
