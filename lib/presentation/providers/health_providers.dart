import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/health_measurement.dart';
import '../../data/models/health_metric_type.dart';
import '../../data/repositories/health_repository_provider.dart';

/// The most recent measurement of a given [HealthMetricType], or null if
/// none is available.
final latestMeasurementProvider =
    FutureProvider.family<HealthMeasurement?, HealthMetricType>((
      ref,
      type,
    ) {
      final repository = ref.watch(healthRepositoryProvider);
      return repository.getLatestMeasurement(type);
    });

/// Recent measurement history for a given [HealthMetricType], newest first.
final measurementHistoryProvider =
    FutureProvider.family<List<HealthMeasurement>, HealthMetricType>((
      ref,
      type,
    ) {
      final repository = ref.watch(healthRepositoryProvider);
      return repository.getMeasurementHistory(type);
    });
