import '../models/health_measurement.dart';
import '../models/health_metric_type.dart';
import 'health_repository.dart';

/// [HealthRepository] backed by a real Galaxy Watch via the Samsung Health
/// Sensor SDK.
///
/// STATUS (Milestone 4): NOT YET FUNCTIONAL. Samsung Health Sensor SDK
/// integration could not be implemented in this milestone because:
///
/// 1. The SDK download requires signing in with a Samsung Developer
///    account (verified: the download link redirects to
///    account.samsung.com sign-in) - this cannot and should not be done
///    autonomously.
/// 2. Without the SDK artifact, the exact Kotlin API surface (tracker
///    class/method names) could not be verified against live official
///    documentation, and the project rules forbid guessing SDK APIs.
/// 3. No physical Galaxy Watch4 is connected to the development machine,
///    and the SDK explicitly does not support emulators - so hardware
///    testing is unavailable regardless.
///
/// See README "Galaxy Watch4 integration status" for full details and next
/// steps. This class exists so the repository abstraction and Dashboard
/// wiring are ready to receive real data the moment the SDK integration is
/// completed - without any UI changes.
class SamsungHealthRepository implements HealthRepository {
  const SamsungHealthRepository();

  @override
  Future<HealthMeasurement?> getLatestMeasurement(
    HealthMetricType type,
  ) async {
    // No real Watch data source is wired up yet - never fabricate a
    // measurement. Returning null here is honest and matches how the UI
    // already handles "no data available".
    return null;
  }

  @override
  Future<List<HealthMeasurement>> getMeasurementHistory(
    HealthMetricType type, {
    int limit = 50,
  }) async {
    return const [];
  }
}
