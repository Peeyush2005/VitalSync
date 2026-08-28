import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/health_measurement.dart';
import '../../data/models/health_metric_type.dart';
import '../../data/repositories/health_repository_provider.dart';

/// The most recent measurement of a given [HealthMetricType], or null if
/// none is available yet. Re-evaluates reactively upon new incoming sensor readings.
final latestMeasurementProvider =
    StreamProvider.family<HealthMeasurement?, HealthMetricType>((
      ref,
      type,
    ) {
      final repository = ref.watch(healthRepositoryProvider);
      return repository.watchLatestMeasurement(type);
    });

/// Recent measurement history for a given [HealthMetricType], newest first.
/// Re-evaluates reactively upon new incoming sensor readings.
final measurementHistoryProvider =
    StreamProvider.family<List<HealthMeasurement>, HealthMetricType>((
      ref,
      type,
    ) {
      final repository = ref.watch(healthRepositoryProvider);
      return repository.watchMeasurementHistory(type);
    });
