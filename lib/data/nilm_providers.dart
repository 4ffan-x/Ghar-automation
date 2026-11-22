import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/nilm/nilm_engine.dart';
import 'monitor_providers.dart';
import 'repositories/nilm_repository.dart';

final nilmRepositoryProvider = Provider<NilmRepository>((ref) {
  throw StateError('NilmRepository must be provided at the app root.');
});

final nilmInsightsProvider = FutureProvider<NilmInsightSnapshot>((ref) async {
  final totals = await ref.watch(energyTotalsProvider.future);
  return ref
      .watch(nilmRepositoryProvider)
      .createSnapshot(measuredTotalKwh: totals.todayKwh);
});
